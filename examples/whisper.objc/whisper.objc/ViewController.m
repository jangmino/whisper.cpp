//
//  ViewController.m
//  whisper.objc
//
//  Created by Georgi Gerganov on 23.10.22.
//

#import "ViewController.h"

#import "whisper.h"

#define NUM_BYTES_PER_BUFFER 16*1024

// callback used to process captured audio
void AudioInputCallback(void * inUserData,
                        AudioQueueRef inAQ,
                        AudioQueueBufferRef inBuffer,
                        const AudioTimeStamp * inStartTime,
                        UInt32 inNumberPacketDescriptions,
                        const AudioStreamPacketDescription * inPacketDescs);

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UILabel    *labelStatusInp;
@property (weak, nonatomic) IBOutlet UIButton   *buttonToggleCapture;
@property (weak, nonatomic) IBOutlet UIButton   *buttonTranscribe;
@property (weak, nonatomic) IBOutlet UIButton   *buttonRealtime;
@property (weak, nonatomic) IBOutlet UITextView *textviewResult;
@property (weak, nonatomic) IBOutlet UITextView *understandingResult;

@end

@implementation ViewController

- (void)setupAudioFormat:(AudioStreamBasicDescription*)format
{
    format->mSampleRate       = WHISPER_SAMPLE_RATE;
    format->mFormatID         = kAudioFormatLinearPCM;
    format->mFramesPerPacket  = 1;
    format->mChannelsPerFrame = 1;
    format->mBytesPerFrame    = 2;
    format->mBytesPerPacket   = 2;
    format->mBitsPerChannel   = 16;
    format->mReserved         = 0;
    format->mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // initialize audio format and buffers
    [self setupAudioFormat:&stateInp.dataFormat];

    stateInp.n_samples = 0;
    stateInp.audioBufferI16 = malloc(MAX_AUDIO_SEC*SAMPLE_RATE*sizeof(int16_t));
    stateInp.audioBufferF32 = malloc(MAX_AUDIO_SEC*SAMPLE_RATE*sizeof(float));

    stateInp.isTranscribing = false;
    stateInp.isRealtime = false;
    
    // 버튼 숨김
    self.buttonToggleCapture.hidden = YES;
    self.buttonTranscribe.hidden = YES;
    self.buttonRealtime.hidden = YES;
    
    self.textviewResult.text = @"음성 인식 모델 초기화 중...";
    
    // 로딩 인디케이터 초기화 및 화면 중앙에 배치
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.center = self.view.center;
    [self.view addSubview:self.loadingIndicator];
    
    // 로딩 인디케이터 시작
    [self.loadingIndicator startAnimating];

    // 비동기 모델 로딩 작업 시작
    [self performAsyncLoading];
}

- (void) performAsyncLoading {
    // Move whisper.cpp initialization to a background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // load the model
        NSString *modelPath = [[NSBundle mainBundle] pathForResource:@"ggml-medium" ofType:@"bin"];
        // check if the model exists
        if (![[NSFileManager defaultManager] fileExistsAtPath:modelPath]) {
            NSLog(@"Model file not found");
            return;
        }

        NSLog(@"Loading model from %@", modelPath);

        // create ggml context
        struct whisper_context_params cparams = whisper_context_default_params();
    #if TARGET_OS_SIMULATOR
        cparams.use_gpu = false;
        NSLog(@"Running on simulator, using CPU");
    #endif
        void* ctx = whisper_init_from_file_with_params([modelPath UTF8String], cparams);

        // Switch back to the main thread to update any UI or state
        dispatch_async(dispatch_get_main_queue(), ^{
//            __strong typeof(weakSelf) strongSelf = weakSelf;
            // check if the model was loaded successfully
            if (ctx == NULL) {
                NSLog(@"Failed to load model");
            } else {
                NSLog(@"Loading is done");
                
                // 인디케이터 숨김
                [self.loadingIndicator stopAnimating];
                
                // Update the context and UI if necessary
                self->stateInp.ctx = ctx;
                // Perform any other UI updates or post-loading operations here
                
                // 버튼 활성화
                self.buttonToggleCapture.hidden = NO;
                self.buttonTranscribe.hidden = NO;
//                self.buttonRealtime.hidden = NO;
                
                self.textviewResult.text = @"음성 인식 가능";
            }
        });
    });
}


-(IBAction) stopCapturing {
    NSLog(@"Stop capturing");

    _labelStatusInp.text = @"Status: Idle";

    [_buttonToggleCapture setTitle:@"Start capturing" forState:UIControlStateNormal];
    [_buttonToggleCapture setBackgroundColor:[UIColor grayColor]];

    stateInp.isCapturing = false;

    AudioQueueStop(stateInp.queue, true);
    for (int i = 0; i < NUM_BUFFERS; i++) {
        AudioQueueFreeBuffer(stateInp.queue, stateInp.buffers[i]);
    }

    AudioQueueDispose(stateInp.queue, true);
}

- (IBAction)toggleCapture:(id)sender {
    if (stateInp.isCapturing) {
        // stop capturing
        [self stopCapturing];

        return;
    }

    // initiate audio capturing
    NSLog(@"Start capturing");
    
    // clear understandingResult
    _understandingResult.text = @"";

    stateInp.n_samples = 0;
    stateInp.vc = (__bridge void *)(self);

    OSStatus status = AudioQueueNewInput(&stateInp.dataFormat,
                                         AudioInputCallback,
                                         &stateInp,
                                         CFRunLoopGetCurrent(),
                                         kCFRunLoopCommonModes,
                                         0,
                                         &stateInp.queue);

    if (status == 0) {
        for (int i = 0; i < NUM_BUFFERS; i++) {
            AudioQueueAllocateBuffer(stateInp.queue, NUM_BYTES_PER_BUFFER, &stateInp.buffers[i]);
            AudioQueueEnqueueBuffer (stateInp.queue, stateInp.buffers[i], 0, NULL);
        }

        stateInp.isCapturing = true;
        status = AudioQueueStart(stateInp.queue, NULL);
        if (status == 0) {
            _labelStatusInp.text = @"Status: Capturing";
            [sender setTitle:@"Stop Capturing" forState:UIControlStateNormal];
            [_buttonToggleCapture setBackgroundColor:[UIColor redColor]];
        }
    }

    if (status != 0) {
        [self stopCapturing];
    }
}

- (IBAction)onTranscribePrepare:(id)sender {
    _textviewResult.text = @"Processing - please wait ...";

    if (stateInp.isRealtime) {
        [self onRealtime:(id)sender];
    }

    if (stateInp.isCapturing) {
        [self stopCapturing];
    }
}

- (IBAction)onRealtime:(id)sender {
    stateInp.isRealtime = !stateInp.isRealtime;

    if (stateInp.isRealtime) {
        [_buttonRealtime setBackgroundColor:[UIColor greenColor]];
    } else {
        [_buttonRealtime setBackgroundColor:[UIColor grayColor]];
    }

    NSLog(@"Realtime: %@", stateInp.isRealtime ? @"ON" : @"OFF");
}

- (IBAction)onTranscribe:(id)sender {
    if (stateInp.isTranscribing) {
        return;
    }

    NSLog(@"Processing %d samples", stateInp.n_samples);

    stateInp.isTranscribing = true;

    // dispatch the model to a background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // process captured audio
        // convert I16 to F32
        for (int i = 0; i < self->stateInp.n_samples; i++) {
            self->stateInp.audioBufferF32[i] = (float)self->stateInp.audioBufferI16[i] / 32768.0f;
        }
        
        // run the model
        struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        
        // get maximum number of threads on this device (max 8)
        const int max_threads = MIN(8, (int)[[NSProcessInfo processInfo] processorCount]);
        
        params.print_realtime   = true;
        params.print_progress   = false;
        params.print_timestamps = true;
        params.print_special    = false;
        params.translate        = false;
        //        params.language         = "en";
        params.language         = "ko";
        params.n_threads        = max_threads;
        params.offset_ms        = 0;
        params.no_context       = true;
        params.single_segment   = self->stateInp.isRealtime;
        params.no_timestamps    = params.single_segment;
        
        CFTimeInterval startTime = CACurrentMediaTime();
        
        whisper_reset_timings(self->stateInp.ctx);
        
        if (whisper_full(self->stateInp.ctx, params, self->stateInp.audioBufferF32, self->stateInp.n_samples) != 0) {
            NSLog(@"Failed to run the model");
            self->_textviewResult.text = @"Failed to run the model";
            
            return;
        }
        
        whisper_print_timings(self->stateInp.ctx);
        
        CFTimeInterval endTime = CACurrentMediaTime();
        
        NSLog(@"\nProcessing time: %5.3f, on %d threads", endTime - startTime, params.n_threads);
        
        // result text
        NSString *result = @"";
        
        int n_segments = whisper_full_n_segments(self->stateInp.ctx);
        for (int i = 0; i < n_segments; i++) {
            const char * text_cur = whisper_full_get_segment_text(self->stateInp.ctx, i);

            // append the text to the result
            result = [result stringByAppendingString:[NSString stringWithUTF8String:text_cur]];
        }
        NSString *pureText = result;

        const float tRecording = (float)self->stateInp.n_samples / (float)self->stateInp.dataFormat.mSampleRate;

        // append processing time
        result = [result stringByAppendingString:[NSString stringWithFormat:@"\n\n[recording time:  %5.3f s]", tRecording]];
        result = [result stringByAppendingString:[NSString stringWithFormat:@"  \n[processing time: %5.3f s]", endTime - startTime]];

        // dispatch the result to the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_textviewResult.text = result;
            self->stateInp.isTranscribing = false;
        });
        
        // request to LLM server
        [self sendServerRequestWithText:pureText];

    });
}

//
// Callback implementation
//

void AudioInputCallback(void * inUserData,
                        AudioQueueRef inAQ,
                        AudioQueueBufferRef inBuffer,
                        const AudioTimeStamp * inStartTime,
                        UInt32 inNumberPacketDescriptions,
                        const AudioStreamPacketDescription * inPacketDescs)
{
    StateInp * stateInp = (StateInp*)inUserData;

    if (!stateInp->isCapturing) {
        NSLog(@"Not capturing, ignoring audio");
        return;
    }

    const int n = inBuffer->mAudioDataByteSize / 2;

    NSLog(@"Captured %d new samples", n);

    if (stateInp->n_samples + n > MAX_AUDIO_SEC*SAMPLE_RATE) {
        NSLog(@"Too much audio data, ignoring");

        dispatch_async(dispatch_get_main_queue(), ^{
            ViewController * vc = (__bridge ViewController *)(stateInp->vc);
            [vc stopCapturing];
        });

        return;
    }

    for (int i = 0; i < n; i++) {
        stateInp->audioBufferI16[stateInp->n_samples + i] = ((short*)inBuffer->mAudioData)[i];
    }

    stateInp->n_samples += n;

    // put the buffer back in the queue
    AudioQueueEnqueueBuffer(stateInp->queue, inBuffer, 0, NULL);

    if (stateInp->isRealtime) {
        // dipatch onTranscribe() to the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            ViewController * vc = (__bridge ViewController *)(stateInp->vc);
            [vc onTranscribe:nil];
        });
    }
}

- (void)sendServerRequestWithText:(NSString *)text {
    NSString *urlString = @"https://vc13jvtdhj.execute-api.us-west-2.amazonaws.com/test/order";
    NSURL *url = [NSURL URLWithString:urlString];

    NSString *instructionPromptTemplate = @"### 다음 주문 문장을 분석하여 음식명, 옵션명, 수량을 추출해줘.\n\n### 명령: %@ ### 응답:\n";

    NSString *prompt = [NSString stringWithFormat:instructionPromptTemplate, text];
    NSUInteger promptLength = [prompt length];

    NSDictionary *dataDict = @{
        @"inputs": prompt,
        @"parameters": @{
                @"do_sample": @YES,
                @"temperature": @0.3,
                @"top_k": @50,
                @"max_new_tokens": @256,
                @"repetition_penalty": @1.03,
                @"stop": @[@"</s>"]
        }
    };
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dataDict options:kNilOptions error:&error];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:jsonData];

    NSURLSession *session = [NSURLSession sharedSession];
    __weak typeof(self) weakSelf = self; // Avoid retain cycles
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"Error: %@", error);
        } else {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSString *infoText = @"";
            NSLog(@"Response status code: %ld", (long)[httpResponse statusCode]);

            if ([httpResponse statusCode] == 200) {
                NSError *parseError = nil;
                id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
                
                if (!parseError) {
                    if ([jsonObject isKindOfClass:[NSArray class]]) {
                        NSArray *responseArray = (NSArray *)jsonObject;
                        NSDictionary *firstDict = responseArray[0];
                        
                        if ([firstDict objectForKey:@"generated_text"] != nil) {
                            NSString *generatedText = firstDict[@"generated_text"];
                            NSString *trimmedText = [generatedText substringFromIndex:promptLength];

                            infoText = trimmedText;
                        } else {
                            infoText = @"'generated_text' 키가 존재하지 않습니다.";
                        }

                    } else {
                        infoText = [NSString stringWithFormat:@"API Gateway -> LLM Server 연결 이상: %@", jsonObject];
                    }
                } else {
                    infoText = [NSString stringWithFormat:@"JSON 파싱 오류: %@", parseError];
                }
            } else {
                infoText = @"API Gateway 연결 이상";
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                strongSelf->_understandingResult.text = infoText;
            });
        }
    }];

    [dataTask resume];
}


@end

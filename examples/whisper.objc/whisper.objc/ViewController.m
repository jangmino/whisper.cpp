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

@interface ViewController () <UITableViewDataSource>

@property (weak, nonatomic) IBOutlet UILabel    *labelStatusInp;
@property (weak, nonatomic) IBOutlet UIButton   *buttonToggleCapture;
@property (weak, nonatomic) IBOutlet UIButton   *buttonTranscribe;
@property (weak, nonatomic) IBOutlet UIButton   *buttonRealtime;
@property (weak, nonatomic) IBOutlet UITextView *textviewResult;
@property (weak, nonatomic) IBOutlet UITextView *informationText;

@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (strong, nonatomic) NSArray *dataItems; // 테이블 뷰에 표시될 데이터 배열

@end

@implementation ViewController



- (void)viewDidLoad {
    [super viewDidLoad];
    
    _buttonRealtime.hidden = YES;
    
    self.tableView.dataSource = self;
    
//    // 2x3 행렬 데이터 생성
//    NSString *row1 = @"음식명: 짜장면, 옵션명: 곱배기, 수량: 1";
//    NSString *row2 = @"음식명: 아메리카노, 옵션명: 그랑데, 수량: 3";

    // 전체 데이터를 dataItems 배열에 저장
//    self.dataItems = @[row1, row2];
    
    self.dataItems = @[];
    
}

-(IBAction) stopCapturing {
    NSLog(@"녹음 중지");

    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(self) strongSelf = self;
        strongSelf->_labelStatusInp.text = @"Status: Idle";
        [strongSelf->_buttonToggleCapture setTitle:@"녹음 시작" forState:UIControlStateNormal];
        [strongSelf->_buttonToggleCapture setBackgroundColor:[UIColor grayColor]];
    });

    _stateInp.isCapturing = false;

    AudioQueueStop(_stateInp.queue, true);
    for (int i = 0; i < NUM_BUFFERS; i++) {
        AudioQueueFreeBuffer(_stateInp.queue, _stateInp.buffers[i]);
    }

    AudioQueueDispose(_stateInp.queue, true);
}

- (IBAction)toggleCapture:(id)sender {
    if (_stateInp.isCapturing) {
        // stop capturing
        [self stopCapturing];

        return;
    }

    // initiate audio capturing
    NSLog(@"녹음 시작");
    
    
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(self) strongSelf = self;
        strongSelf->_dataItems = @[];
        strongSelf->_textviewResult.text = @"음성 인식 결과";
        strongSelf->_informationText.text = @"";
        [strongSelf->_tableView reloadData];
    });

    _stateInp.n_samples = 0;
    _stateInp.vc = (__bridge void *)(self);

    OSStatus status = AudioQueueNewInput(&_stateInp.dataFormat,
                                         AudioInputCallback,
                                         &_stateInp,
                                         CFRunLoopGetCurrent(),
                                         kCFRunLoopCommonModes,
                                         0,
                                         &_stateInp.queue);

    if (status == 0) {
        for (int i = 0; i < NUM_BUFFERS; i++) {
            AudioQueueAllocateBuffer(_stateInp.queue, NUM_BYTES_PER_BUFFER, &_stateInp.buffers[i]);
            AudioQueueEnqueueBuffer (_stateInp.queue, _stateInp.buffers[i], 0, NULL);
        }

        _stateInp.isCapturing = true;
        status = AudioQueueStart(_stateInp.queue, NULL);
        if (status == 0) {
            _labelStatusInp.text = @"Status: Capturing";
            [sender setTitle:@"녹음 중지" forState:UIControlStateNormal];
            [_buttonToggleCapture setBackgroundColor:[UIColor redColor]];
        }
    }

    if (status != 0) {
        [self stopCapturing];
    }
}

- (IBAction)onTranscribePrepare:(id)sender {
    _informationText.text = @"Processing - please wait ...";

    if (_stateInp.isRealtime) {
        [self onRealtime:(id)sender];
    }

    if (_stateInp.isCapturing) {
        [self stopCapturing];
    }
}

- (IBAction)onRealtime:(id)sender {
    _stateInp.isRealtime = !_stateInp.isRealtime;

    if (_stateInp.isRealtime) {
        [_buttonRealtime setBackgroundColor:[UIColor greenColor]];
    } else {
        [_buttonRealtime setBackgroundColor:[UIColor grayColor]];
    }

    NSLog(@"Realtime: %@", _stateInp.isRealtime ? @"ON" : @"OFF");
}

- (IBAction)onTranscribe:(id)sender {
//    // 디버그
//    [self sendServerRequestWithText:@"소금빵 3개 주세요"];
//    return;
//    // 디버그
    if (_stateInp.isTranscribing) {
        return;
    }

    NSLog(@"Processing %d samples", _stateInp.n_samples);

    _stateInp.isTranscribing = true;

    // dispatch the model to a background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // process captured audio
        // convert I16 to F32
        for (int i = 0; i < self->_stateInp.n_samples; i++) {
            self->_stateInp.audioBufferF32[i] = (float)self->_stateInp.audioBufferI16[i] / 32768.0f;
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
        params.single_segment   = self->_stateInp.isRealtime;
        params.no_timestamps    = params.single_segment;
        
        CFTimeInterval startTime = CACurrentMediaTime();
        
        whisper_reset_timings(self->_stateInp.ctx);
        
        if (whisper_full(self->_stateInp.ctx, params, self->_stateInp.audioBufferF32, self->_stateInp.n_samples) != 0) {
            NSLog(@"Failed to run the model");
            self->_informationText.text = @"Failed to run the model";
            
            return;
        }
        
        whisper_print_timings(self->_stateInp.ctx);
        
        CFTimeInterval endTime = CACurrentMediaTime();
        
        NSLog(@"\nProcessing time: %5.3f, on %d threads", endTime - startTime, params.n_threads);
        
        // result text
        NSString *result = @"음성 인식 결과\n\n";
        
        int n_segments = whisper_full_n_segments(self->_stateInp.ctx);
        for (int i = 0; i < n_segments; i++) {
            const char * text_cur = whisper_full_get_segment_text(self->_stateInp.ctx, i);

            // append the text to the result
            result = [result stringByAppendingString:[NSString stringWithUTF8String:text_cur]];
        }
        NSString *pureText = result;

        const float tRecording = (float)self->_stateInp.n_samples / (float)self->_stateInp.dataFormat.mSampleRate;

        // append processing time
        NSString *infomationResult = @"";
        infomationResult = [infomationResult stringByAppendingString:[NSString stringWithFormat:@"\n\n[recording time:  %5.3f s]", tRecording]];
        infomationResult = [infomationResult stringByAppendingString:[NSString stringWithFormat:@"  \n[processing time: %5.3f s]", endTime - startTime]];

        // dispatch the result to the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_textviewResult.text = result;
            self->_informationText.text = infomationResult;
            self->_stateInp.isTranscribing = false;
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

- (NSString *)serverURLFromPlist {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Config" ofType:@"plist"];
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:path];
    NSString *urlString = config[@"ServerURL"];
    return urlString;
}

- (void)sendServerRequestWithText:(NSString *)text {
    // jangmin.oh private aws gateway
//    NSString *urlString = @"https://vc13jvtdhj.execute-api.us-west-2.amazonaws.com/test/order";
    
    // manna-aws gateway
//    NSString *urlString = @"https://kn8m633eaf.execute-api.us-west-2.amazonaws.com/test/order";
    
    NSString *urlString = [self serverURLFromPlist];
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
            BOOL isNormal = NO;
            

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
                            isNormal = YES;
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
                NSMutableArray* parsedItems = [strongSelf parseStringAndReloadTableView: infoText];
                
                if (isNormal == NO) {
                    strongSelf->_dataItems = @[];
                    strongSelf->_informationText.text = infoText;
                } else {
                    strongSelf->_dataItems = [parsedItems copy];
                }
                // UITableView 갱신
                [strongSelf->_tableView reloadData];
            });
        }
    }];

    [dataTask resume];
}

- (NSMutableArray *)parseStringAndReloadTableView:(NSString *)inputString {
    NSArray *results = [inputString componentsSeparatedByString:@"\n"];
    
    NSMutableArray *parsedItems = [NSMutableArray array];
    for (NSString *result in results) {
        // 각 줄에서 '음식명', '옵션', '수량'을 추출합니다.
        NSString *trimmedResult = [result stringByReplacingOccurrencesOfString:@"- 분석 결과 " withString:@""];
        NSArray *splitNumbers = [trimmedResult componentsSeparatedByString:@": "];
        if (splitNumbers.count > 1) {
            trimmedResult = splitNumbers[1]; // 숫자 이후 문자열을 가져옵니다.
        }
        // 필요한 경우, 추가적인 정제 작업을 수행합니다.
        [parsedItems addObject:trimmedResult];
    }
    
    return parsedItems;
}


#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.dataItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CellIdentifier"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CellIdentifier"];
    }

    // 각 행의 데이터를 가져옴
    NSString *row = self.dataItems[indexPath.row];
    // 행 데이터를 쉼표로 구분된 문자열로 변환
//    NSString *rowString = [row componentsJoinedByString:@", "];

    // 셀에 행 데이터 표시
    cell.textLabel.text = row;

    return cell;
}


@end

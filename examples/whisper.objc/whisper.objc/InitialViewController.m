//
//  InitialViewController.m
//  my-order-genie
//
//  Created by 오장민 on 2/3/24.
//

#import "InitialViewController.h"
#import "ViewController.h"
#import "whisper.h"

@interface InitialViewController ()

@end

@implementation InitialViewController

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
    // Do any additional setup after loading the view.
    NSLog(@"Hello It's InitialViewController");
    
    // initialize audio format and buffers
    [self setupAudioFormat:&stateInp.dataFormat];

    stateInp.n_samples = 0;
    stateInp.audioBufferI16 = malloc(MAX_AUDIO_SEC*SAMPLE_RATE*sizeof(int16_t));
    stateInp.audioBufferF32 = malloc(MAX_AUDIO_SEC*SAMPLE_RATE*sizeof(float));

    stateInp.isTranscribing = false;
    stateInp.isRealtime = false;
    
    // 로딩 인디케이터 초기화 및 화면 중앙에 배치
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.center = self.view.center;
    [self.view addSubview:self.loadingIndicator];
    
    // 로딩 인디케이터 시작
    [self.loadingIndicator startAnimating];

    // 비동기 모델 로딩 작업 시작
    [self initializeAndLoadModel];
}



- (void)initializeAndLoadModel {
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
        // 모델 로딩 완료 후 ViewController로 화면 전환
        dispatch_async(dispatch_get_main_queue(), ^{
            self->stateInp.ctx = ctx;
            if (ctx == NULL) {
                NSLog(@"Failed to load model");
            }

            [self.loadingIndicator stopAnimating];
            [self transitionToMainViewController];
        });
    });
}

- (void)transitionToMainViewController {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil]; 
    ViewController *mainViewController = [storyboard instantiateViewControllerWithIdentifier:@"MainViewController"];
    mainViewController.stateInp = stateInp;
    [self presentViewController:mainViewController animated:YES completion:nil];
    
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end

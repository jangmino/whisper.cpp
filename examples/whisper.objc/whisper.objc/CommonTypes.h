//
//  CommonTypes.h
//  whisper.objc
//
//  Created by 오장민 on 2/3/24.
//

#ifndef CommonTypes_h
#define CommonTypes_h

// CommonTypes.h 파일 내용
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioQueue.h>

#define NUM_BUFFERS 3
#define MAX_AUDIO_SEC 30
#define SAMPLE_RATE 16000

struct whisper_context;

typedef struct StateInp {
    int ggwaveId;
    bool isCapturing;
    bool isTranscribing;
    bool isRealtime;

    AudioQueueRef queue;
    AudioStreamBasicDescription dataFormat;
    AudioQueueBufferRef buffers[NUM_BUFFERS];

    int n_samples;
    int16_t * audioBufferI16;
    float   * audioBufferF32;

    struct whisper_context * ctx;

    void * vc;
} StateInp;



#endif /* CommonTypes_h */

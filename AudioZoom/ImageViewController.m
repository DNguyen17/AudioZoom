//
//  ImageViewController.m
//  AudioZoom
//
//  Created by Danh Nguyen on 4/15/18.
//  Copyright © 2018 Danh Nguyen. All rights reserved.
//

#import "ImageViewController.h"
#import "Novocaine.h"
#import "CircularBuffer.h"
#import "FFTHelper.h"
#import "PeakFinder.h"

#define BUFFER_SIZE 2048*4
#define RANGE_OF_AVERAGE 25
#define FREQUENCY 19000


@interface ImageViewController ()
@property (strong, nonatomic) Novocaine *audioManager;
@property (strong, nonatomic) CircularBuffer *buffer;
@property (strong, nonatomic) FFTHelper *fftHelper;
@property (strong, nonatomic) IBOutlet UIImageView* imageView;
@property double baselineLeftAverage;
@property double baselineRightAverage;
@property NSArray *imageNames;
@property int imageIndex;
@end

@implementation ImageViewController

-(Novocaine*)audioManager{
    if(!_audioManager){
        _audioManager = [Novocaine audioManager];
    }
    return _audioManager;
}


-(CircularBuffer*)buffer{
    if(!_buffer){
        _buffer = [[CircularBuffer alloc]initWithNumChannels:1 andBufferSize:BUFFER_SIZE];
    }
    return _buffer;
}

-(FFTHelper*)fftHelper{
    if(!_fftHelper){
        _fftHelper = [[FFTHelper alloc]initWithFFTSize:BUFFER_SIZE];
    }
    
    return _fftHelper;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.imageNames = @[@"Stock", @"Stock2", @"Stock3"];
    self.imageIndex = 0;
    UIImage *image = [UIImage imageNamed: self.imageNames[self.imageIndex]];
    [self.imageView setImage:image];
    
    // initialize input block
    __block ImageViewController * __weak  weakSelf = self;
    [self.audioManager setInputBlock:^(float *data, UInt32 numFrames, UInt32 numChannels){
        [weakSelf.buffer addNewFloatData:data withNumSamples:numFrames];
    }];
    
    // play sound
    __block double phase = 0.0;
    double phaseIncrement = 2.0*M_PI*((double)FREQUENCY)/((double)self.audioManager.samplingRate);
    double phaseMax = 2.0*M_PI;
    
    [self.audioManager setOutputBlock:^(float* data, UInt32 numFrames, UInt32 numChannels){
        for(int i=0; i<numFrames;++i){
            for(int j=0;j<numChannels;++j){
                data[numChannels*i+j] = sin(phase);
            }
            phase+=phaseIncrement;
            if (phase>phaseMax){
                phase -= phaseMax;
            }
        }
        
    }];
    
    [self.audioManager play];
    
    // give 1 second so calibration will work
    [NSTimer scheduledTimerWithTimeInterval:1.0
                                     target:self
                                   selector:@selector(calibrate:)
                                   userInfo:nil
                                    repeats:NO];
    
    // run doppler loop in background
    [NSTimer scheduledTimerWithTimeInterval:0.2f
                                     target:self
                                   selector:@selector(calculateDoppler:)
                                   userInfo:nil
                                    repeats:YES];
}

-(void)viewDidDisappear:(BOOL)animated {
    [self.audioManager setOutputBlock:nil];
    [self.audioManager pause];
    [super viewDidDisappear:animated];
    
}

- (void) calculateDoppler:(NSTimer *)timer
{
    //Do calculations.
    __block ImageViewController * __weak weakSelf = self;
    dispatch_queue_t dopplerQueue = dispatch_queue_create("dopplerQueue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(dopplerQueue, ^{
        float* arrayData = malloc(sizeof(float)*BUFFER_SIZE);
        float* fftMagnitude = malloc(sizeof(float)*BUFFER_SIZE/2);
        
        [weakSelf.buffer fetchFreshData:arrayData withNumSamples:BUFFER_SIZE];
        
        // take forward FFT
        [weakSelf.fftHelper performForwardFFTWithData:arrayData
                           andCopydBMagnitudeToBuffer:fftMagnitude];
        
        //right
        double rightValue = [weakSelf calcSideAverage:fftMagnitude
                                              isRight:(YES)];
        
        //left
        double leftValue = [weakSelf calcSideAverage:fftMagnitude
                                             isRight:(NO)];
        
        double threshold = 20; //decibels;
        
        if(rightValue - weakSelf.baselineRightAverage > threshold) {
            NSLog(@"towards");
            if (self.imageIndex < [self.imageNames count]-1) {
                self.imageIndex++;
            } else {
                self.imageIndex = 0;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.imageView setImage:([UIImage imageNamed: self.imageNames[self.imageIndex]])];
            });
        }
        else if (leftValue - weakSelf.baselineLeftAverage > threshold) {
            NSLog(@"away");
            if (self.imageIndex > 0) {
                self.imageIndex--;
            } else {
                self.imageIndex = (int)[self.imageNames count]-1;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.imageView setImage:([UIImage imageNamed: self.imageNames[self.imageIndex]])];
            });
            
        }
        
        free(arrayData);
        free(fftMagnitude);
    });
    
}

-(double) calcSideAverage: (float*) fftMagnitude
                  isRight:(BOOL) isRight{
    int peakIndex = (int) (((float)19000)/(((float)self.audioManager.samplingRate)/(((float)BUFFER_SIZE))));
    double average = 0;
    if(isRight){
        peakIndex += RANGE_OF_AVERAGE;
    }
    for (int i = peakIndex-RANGE_OF_AVERAGE; i <= peakIndex; ++i) {
        average += fftMagnitude[i];
    }
    average /= RANGE_OF_AVERAGE;
    
    return average;
    
}

-(void) calibrate: (NSTimer *) timer {
    float* arrayData = malloc(sizeof(float)*BUFFER_SIZE);
    float* fftMagnitude = malloc(sizeof(float)*BUFFER_SIZE/2);
    
    [self.buffer fetchFreshData:arrayData withNumSamples:BUFFER_SIZE];
    
    // take forward FFT
    [self.fftHelper performForwardFFTWithData:arrayData
                   andCopydBMagnitudeToBuffer:fftMagnitude];
    
    // defaults by inspection
    self.baselineLeftAverage = -50.0;
    self.baselineRightAverage = -50.0;
    
    float leftAverage = [self calcSideAverage: fftMagnitude
                                      isRight: (NO)];
    if (leftAverage != 0) {
        self.baselineLeftAverage = leftAverage;
    }
    
    float rightAverage = [self calcSideAverage:fftMagnitude
                                       isRight: (YES)];
    if (rightAverage != 0) {
        self.baselineRightAverage = rightAverage;
    }
    
    free(arrayData);
    free(fftMagnitude);
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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

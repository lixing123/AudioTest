//
//  ViewController.m
//  GenerateAudioExample
//
//  Created by 李 行 on 15/2/26.
//  Copyright (c) 2015年 lixing123.com. All rights reserved.
//

#import "ViewController.h"
#import "RecordAudio.h"
#import "PlayAudio.h"
#import "Converter.h"
#import "PlayAndRecord.h"

@interface ViewController ()

@end

@implementation ViewController



- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    /*RecordAudio* record = [[RecordAudio alloc] init];
    [record start];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [record stop];
    });*/
    /*
    PlayAudio* play = [[PlayAudio alloc] init];
    [play start];
    */
    
    /*Converter* converter = [[Converter alloc] init];
    [converter startConvert];
    */
    
    
    PlayAndRecord* playAndRecord = [[PlayAndRecord alloc] init];
    [playAndRecord start];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

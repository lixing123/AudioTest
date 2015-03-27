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
#import "AudioUnitTest.h"

@interface ViewController ()

@end

PlayAndRecord* playAndRecord;
UITextField* textField;
UIButton* submit;

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
    
    /*
    playAndRecord = [[PlayAndRecord alloc] init];
    [playAndRecord start];
    
    textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 320, 100)];
    textField.keyboardType = UIKeyboardTypeDecimalPad;
    textField.placeholder = @"input...";
    [self.view addSubview:textField];
    
    submit = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [submit setTitle:@"Submit" forState:UIControlStateNormal];
    [submit setFrame:CGRectMake(0, 150, 320, 100)];
    [submit addTarget:self action:@selector(submit) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:submit];*/
    
    AudioUnitTest* test = [[AudioUnitTest alloc] init];
    [test start];
}

-(void)submit{
    float factor = [textField.text floatValue];
    [playAndRecord changeEchoFactor:factor];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

//
//  ExtAudioFileMixer.h
//  GenerateAudioExample
//
//  Created by 李 行 on 15/2/26.
//  Copyright (c) 2015年 lixing123.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ExtAudioFileMixer : NSObject

+ (OSStatus)mixAudio:(NSString *)audioPath1
            andAudio:(NSString *)audioPath2
              toFile:(NSString *)outputPath
  preferedSampleRate:(float)sampleRate;

@end

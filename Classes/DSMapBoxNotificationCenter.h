//
//  DSMapBoxNotificationCenter.h
//  MapBoxiPad
//
//  Created by Justin R. Miller on 5/2/11.
//  Copyright 2011 Development Seed. All rights reserved.
//

@interface DSMapBoxNotificationCenter : NSObject

+ (DSMapBoxNotificationCenter *)sharedInstance;

- (void)notifyWithMessage:(NSString *)message;

@end
//
//  AudioEffectPanelController.h
//  Alchemusica
//
//  Created by Toshi Nagata on 2017/10/08.
//  Copyright 2010-2017 Toshi Nagata. All rights reserved.
//
/*
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>
@class AudioEffectLayoutView;

@interface AudioEffectPanelController : NSWindowController {
    IBOutlet NSSplitView *splitView;
    IBOutlet AudioEffectLayoutView *layoutView;
    IBOutlet NSView *customContainerView;
    IBOutlet NSScrollView *effectLayoutScrollView;
    IBOutlet NSScrollView *effectContentScrollView;
    NSView *customView;
    int busIndex;
    int selectedEffect;
    CGFloat xpos_output;  //  X position of the "Stereo Out" box
}
- (id)initWithBusIndex:(int)idx;
- (CGFloat)xpos_output;
- (int)numberOfChains;
- (IBAction)addEffect:(id)sender;
- (IBAction)addEffectChain:(id)sender;
- (IBAction)removeEffectChain:(id)sender;
- (IBAction)insertEffect:(id)sender;
- (IBAction)changeEffect:(id)sender;
- (IBAction)removeEffect:(id)sender;
- (IBAction)effectButtonPressed:(id)sender;
@end

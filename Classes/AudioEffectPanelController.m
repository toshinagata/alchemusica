//
//  AudioEffectPanelController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 2017/10/09.
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

#import "AudioEffectPanelController.h"
#import "AudioEffectLayoutView.h"
#import "NSWindowControllerAdditions.h"
#import "MDHeaders.h"

enum {
    kAudioEffectPanelStereoInTextTag = 1,
    kAudioEffectPanelChannelTextTag = 3,
    kAudioEffectPanelEffectPlusButtonTag = 4,
    kAudioEffectPanelChannelPlusButtonTag = 5,
    kAudioEffectPanelChannelMinusButtonTag = 6,
    kAudioEffectPanelStereoOutTextTag = 8,
    kAudioEffectPanelEffectBaseTag = 10
};

@implementation AudioEffectPanelController

- (id)initWithBusIndex:(int)idx
{
    self = [super initWithWindowNibName:@"AudioEffectPanel"];
    if (self) {
        busIndex = idx;
    }
    return self;
}

- (void)appendChain
{

}

- (void)removeLastChain
{
    MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(busIndex);
    if (ip->nchains <= 1)
        return;
    if (ip->chains[ip->nchains - 1].neffects > 0)
        return;
    
}

- (void)insertEffectWithName:(NSString *)name atIndex:(int)effectIndex inChain:(int)chainIndex
{
    
}

- (void)replaceEffectName:(NSString *)name atIndex:(int)effectIndex inChain:(int)chainIndex
{

}

- (void)removeEffectAtIndex:(int)effectIndex inChain:(int)chainIndex
{
    
}

- (void)updateWindow
{
    MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(busIndex);
    NSView *view;
    int n, height;
    NSRect r, r1;
    
    //  Resize 'Stereo In' box
    n = ip->nchains;
    view = [[self viewWithTag:kAudioEffectPanelStereoInTextTag] superview];
    r = [view frame];
    height = (n <= 1 ? 21 : 21 + (n - 1) * 29);
    r.origin.y += height - r.size.height;
    r.size.height = height;
    [view setFrame:r];
    
    //  Relocate channel+, channel- buttons
    view = [self viewWithTag:kAudioEffectPanelChannelPlusButtonTag];
    r1 = [view frame];
    r1.origin.y = r.origin.y - r1.size.height;
    [view setFrame:r1];
    view = [self viewWithTag:kAudioEffectPanelChannelMinusButtonTag];
    r1 = [view frame];
    r1.origin.y = r.origin.y - r1.size.height;
    [view setFrame:r1];
    
    
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [[self window] setTitle:[NSString stringWithFormat:@"Audio Effects: Bus %d", busIndex + 1]];
    
    //  Set tag for the NSBox
    
}

#if 0
#pragma mark ====== Delegate methods ======
#endif

- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition ofSubviewAt:(NSInteger)dividerIndex
{
    NSSize size = [[[self window] contentView] bounds].size;
    if (proposedPosition < 42.0)
        return 42.0;
    else if (proposedPosition > size.height - 48.0)
        return size.height - 48.0;
    else return proposedPosition;
}

@end

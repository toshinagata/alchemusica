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
#import "AUViewWindowController.h"
#import "MyPopUpButton.h"
#import "NSWindowControllerAdditions.h"
#import "NSMenuAdditions.h"
#import "MDHeaders.h"

enum {
    kAudioEffectPanelStereoInTextTag = 0,
    kAudioEffectPanelChannelMinusButtonTag = 1,
    kAudioEffectPanelChannelPlusButtonTag = 2,
    kAudioEffectPanelChannelTextTag = 3,
    kAudioEffectPanelStereoOutTextTag = 4,
    kAudioEffectPanelEffectBaseTag = 10
};

static NSString *sAudioEffectPanelShouldUpdate = @"Audio effect panel should update";

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

- (NSMenu *)menuWithEffectNames
{
    int k;
    id item;
    NSMenu *menu;
    MDAudioMusicDeviceInfo *ep;
    menu = [[[NSMenu alloc] init] autorelease];
    for (k = 0; (ep = MDAudioEffectDeviceInfoAtIndex(k)) != NULL; k++) {
        NSString *str2;
        str2 = [NSString stringWithUTF8String:ep->name];
        item = [menu addItemWithTitle:str2 action:nil keyEquivalent:@""];
        [item setTag:k];
        [item setTarget:self];
    }
    return menu;
}

- (NSBox *)enclosingBoxForView:(NSView *)view
{
    NSView *sview;
    for (sview = [view superview]; sview != nil; sview = [sview superview]) {
        if ([sview isKindOfClass:[NSBox class]])
            return (NSBox *)sview;
    }
    return nil;
}

- (void)updateWindow
{
    MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(busIndex);
    NSView *view;
    int n, height, i, j;
    NSRect r, r1;
    NSRect b = [layoutView frame];
    NSFont *font = [NSFont labelFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]];
    NSDictionary *glyphAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                     font, NSFontAttributeName, nil];
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    NSDictionary *redTextAttributes;

    [style setAlignment:NSCenterTextAlignment];
    redTextAttributes = [NSDictionary dictionaryWithObjectsAndKeys: font, NSFontAttributeName, [NSColor redColor], NSForegroundColorAttributeName, style, NSParagraphStyleAttributeName, nil];
    
    //  New height of the layout view (width will be updated later)
    n = ip->nchains;
    height = (n <= 1 ? 52 : 52 + (n - 1) * 25);
    b.size.height = height;
    [layoutView setFrame:b];
    
    //  Resize 'Stereo In' box
    view = [self enclosingBoxForView:[self viewWithTag:kAudioEffectPanelStereoInTextTag]];
    r = [view frame];
    height = (n <= 1 ? 17 : 17 + (n - 1) * 25);
    r.origin.y = b.size.height - (height + 12);
    r.size.height = height;
    [view setFrame:r];
    
    //  Relocate channel+, channel- buttons
    view = [self viewWithTag:kAudioEffectPanelChannelPlusButtonTag];
    r1 = [view frame];
    r1.origin.y = r.origin.y - r1.size.height + 2;
    [view setFrame:r1];
    view = [self viewWithTag:kAudioEffectPanelChannelMinusButtonTag];
    r1 = [view frame];
    r1.origin.y = r.origin.y - r1.size.height + 2;
    [view setFrame:r1];
    if (ip->nchains > 1 && ip->chains[ip->nchains - 1].neffects == 0)
        [(NSButton *)view setEnabled:YES];
    else [(NSButton *)view setEnabled:NO];
    
    xpos_output = 0;
    //  Relocate view for each chain
    for (i = 0; i < n; i++) {
        int base = i * 1000;
        int ybase = b.size.height - 29 - 25 * i;
        int xbase = r.origin.x + r.size.width - 1;
        
        //  Channel "N-N+1" text
        view = [self viewWithTag:base + kAudioEffectPanelChannelTextTag];
        if (view == nil) {
            //  We need to create a NSBox and its enclosing text
            NSString *s;
            view = [self enclosingBoxForView:[self viewWithTag:kAudioEffectPanelChannelTextTag]];
            //  Copy the NSBox
            view = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:view]];
            [layoutView addSubview:view];
            view = [view viewWithTag:kAudioEffectPanelChannelTextTag];
            [(NSTextField *)view setTag:base + kAudioEffectPanelChannelTextTag];
            s = [NSString stringWithFormat:@"%d-%d", i * 2, i * 2 + 1];
            if (ip->chains[i].alive) {
                [(NSTextField *)view setStringValue:s];
            } else {
                [(NSTextField *)view setAttributedStringValue:[[[NSAttributedString alloc] initWithString:s attributes:redTextAttributes] autorelease]];
            }
        }
        view = [self enclosingBoxForView:view];
        r1 = [view frame];
        r1.origin.x = xbase;
        r1.origin.y = ybase;
        [view setFrame:r1];
        xbase += r1.size.width - 1;
        
        //  Effect buttons
        for (j = 0; j <= ip->chains[i].neffects; j++) {
            NSButton *bplus, *bname, *bmenu;
            NSString *str;
            NSSize size;
            int buttonTag = base + kAudioEffectPanelEffectBaseTag + j * 3;

            //  effect+ button
            bplus = (NSButton *)[self viewWithTag:buttonTag];
            if (bplus == nil) {
                //  Copy the button for chain 0, effect 0
                bplus = (NSButton *)[self viewWithTag:kAudioEffectPanelEffectBaseTag];
                bplus = (NSButton *)[NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:bplus]];
                [layoutView addSubview:bplus];
                [bplus setTag:buttonTag];
                [bplus highlight:NO];
            }
            r1 = [bplus frame];
            r1.origin.x = xbase;
            r1.origin.y = ybase + 1;
            [bplus setFrame:r1];
            xbase += r1.size.width - 1;
            if (j == ip->chains[i].neffects)
                break;

            //  Effect button
            str = [NSString stringWithUTF8String:ip->chains[i].effects[j].name];
            size = [str sizeWithAttributes:glyphAttributes];
            r1.origin = NSMakePoint(xbase + 16, ybase);
            r1.size = NSMakeSize((float)ceil(size.width + 10), 17);
            bname = (NSButton *)[self viewWithTag:buttonTag + 1];
            bmenu = (NSButton *)[self viewWithTag:buttonTag + 2];
            if (bname == nil) {
                //  We need to create new buttons
                bname = [[[NSButton alloc] initWithFrame:r1] autorelease];
                [bname setBezelStyle:NSShadowlessSquareBezelStyle];
                [bname setTag:buttonTag + 1];
                [[bname cell] setControlSize:NSSmallControlSize];
                [bname setTarget:self];
                [bname setAction:@selector(effectButtonPressed:)];
                bmenu = [[[NSButton alloc] initWithFrame:r1] autorelease];
                [bmenu setBezelStyle:NSShadowlessSquareBezelStyle];
                [bmenu setTag:buttonTag + 2];
                [bmenu setTarget:self];
                [bmenu setAction:@selector(addEffect:)];
                [bmenu setImage:[MyPopUpButton doubleTriangleImage]];
                [layoutView addSubview:bname];
                [layoutView addSubview:bmenu];
            }
            [bname setAttributedTitle:[[[NSAttributedString alloc] initWithString:str attributes:glyphAttributes] autorelease]];
            [bname setFrame:r1];
            r1.origin.x += r1.size.width - 1;
            r1.size.width = 14;
            [bmenu setFrame:r1];
            if (selectedEffect >= 0 && selectedEffect / 1000 == i && selectedEffect % 1000 == j)
                [bname highlight:YES];
            else [bname highlight:NO];
            xbase = r1.origin.x + r1.size.width - 1;
        }
        
        xbase = r1.origin.x + r1.size.width + 32;
        if (xpos_output < xbase)
            xpos_output = xbase;
    }
    
    //  Relocate 'Stereo Out' box
    view = [self enclosingBoxForView:[self viewWithTag:kAudioEffectPanelStereoOutTextTag]];
    r = [view frame];
    height = 17;
    r.origin.y = b.size.height - (height + 12);
    r.size.height = height;
    r.origin.x = xpos_output;
    [view setFrame:r];
    
    //  Update the width of the layout view
    b.size.width = r.origin.x + r.size.width + 12;
    [layoutView setFrame:b];
    
    [layoutView setNeedsDisplay:YES];
}

- (void)updateRequested:(NSNotification *)aNotification
{
    [self updateWindow];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [[self window] setTitle:[NSString stringWithFormat:@"Audio Effects: Bus %d", busIndex + 1]];
    [layoutView setDataSource:self];
    selectedEffect = 0;
    [[NSNotificationCenter defaultCenter]
     addObserver: self
     selector: @selector(updateRequested:)
     name: sAudioEffectPanelShouldUpdate
     object:nil];
    [effectLayoutScrollView setDrawsBackground:YES];
    [effectLayoutScrollView setBackgroundColor:[NSColor windowBackgroundColor]];
    [effectContentScrollView setDrawsBackground:YES];
    [effectContentScrollView setBackgroundColor:[NSColor windowBackgroundColor]];
    [self updateWindow];
}

- (CGFloat)xpos_output
{
    return xpos_output;
}

- (int)numberOfChains
{
    MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(busIndex);
    return (ip->nchains);
}

- (void)showCustomViewForEffectInChain:(int)chainIndex atIndex:(int)effectIndex
{
    NSView *view;
    MDAudioMusicDeviceInfo *mp;
    MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(busIndex);
    MDAudioEffect *ep;
    if (chainIndex < 0 || chainIndex >= ip->nchains)
        goto hide;
    if (effectIndex < 0 || effectIndex > ip->chains[chainIndex].neffects)
        return;  //  This cannot happen
    ep = ip->chains[chainIndex].effects + effectIndex;
    mp = MDAudioEffectDeviceInfoAtIndex(ep->effectDeviceIndex);
    view = [AUViewWindowController getCocoaViewForAudioUnit:ep->unit defaultViewSize:NSMakeSize(100, 100)];
    if (view != nil) {
        NSRect b = [view bounds];
        if (customView != nil)
            [customView removeFromSuperview];
        customView = nil;
        [customContainerView setFrame:b];
        [customContainerView addSubview:view];
        customView = view;
        return;
    }
hide:
    /*  Hide the view  */
    if (customView != nil) {
        [customView removeFromSuperview];
        customView = nil;
    }
}

#if 0
#pragma mark ====== Actions ======
#endif

- (IBAction)effectButtonPressed:(id)sender
{
    int tag = [sender tag];
    int chainIndex = tag / 1000;
    int itemOffset = tag % 1000 - kAudioEffectPanelEffectBaseTag;
    int effectIndex = itemOffset / 3;
    selectedEffect = chainIndex * 1000 + effectIndex;
    [[NSNotificationQueue defaultQueue] enqueueNotification: [NSNotification notificationWithName: sAudioEffectPanelShouldUpdate object: self] postingStyle: NSPostWhenIdle];
}

- (IBAction)addEffect:(id)sender
{
    NSMenu *menu;
    id item;
    int i;
    int tag = [sender tag];
    int chainIndex = tag / 1000;
    int itemOffset = tag % 1000 - kAudioEffectPanelEffectBaseTag;
    int effectIndex = itemOffset / 3;
    int insert = (itemOffset % 3 == 0);
    MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(busIndex);
    if (chainIndex < 0 || chainIndex >= ip->nchains)
        return;  //  This cannot happen
    if (effectIndex < 0 || effectIndex > ip->chains[chainIndex].neffects)
        return;  //  This cannot happen
    menu = [self menuWithEffectNames];
    for (i = [menu numberOfItems] - 1; i >= 0; i--) {
        item = [menu itemAtIndex:i];
        [item setAction:(insert ? @selector(insertEffect:) : @selector(changeEffect:))];
        [item setTag:chainIndex * 1000000 + effectIndex * 1000 + i];
    }
    if (!insert) {
        [menu addItem:[NSMenuItem separatorItem]];
        item = [menu addItemWithTitle:@"Remove this effect" action:@selector(removeEffect:) keyEquivalent:@""];
        [item setTag:chainIndex * 1000000 + effectIndex * 1000 + 999];
    }
    [menu changeMenuTitleAttributes:[NSDictionary dictionaryWithObject:[NSFont labelFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]] forKey:NSFontAttributeName]];
    [NSMenu popUpContextMenu:menu withEvent:[NSApp currentEvent] forView:sender];
}

- (IBAction)addEffectChain:(id)sender
{
    MDAudioAppendEffectChain(busIndex);
    [self updateWindow];
}

- (IBAction)removeEffectChain:(id)sender
{
    NSView *view;
    int tagbase;
    MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(busIndex);
    if (ip->nchains <= 1 || ip->chains[ip->nchains - 1].neffects != 0)
        return;  /*  Do nothing  */
    MDAudioRemoveLastEffectChain(busIndex);
    /*  Remove 'N-N+1' box and effect+ button  */
    tagbase = ip->nchains * 1000;
    view = [layoutView viewWithTag:tagbase + kAudioEffectPanelChannelTextTag];
    if (view != nil && (view = [self enclosingBoxForView:view]) != nil)
        [view removeFromSuperview];
    view = [layoutView viewWithTag:tagbase + kAudioEffectPanelEffectBaseTag];
    if (view != nil)
        [view removeFromSuperview];
    [self updateWindow];
}

- (void)changeEffect:(id)sender
{
    int tag = [sender tag];
    int chainIndex = tag / 1000000;
    int effectIndex = (tag / 1000) % 1000;
    int effectID = tag % 1000;
    MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(busIndex);
    if (chainIndex < 0 || chainIndex >= ip->nchains)
        return;  //  This cannot happen
    MDAudioChangeEffect(busIndex, chainIndex, effectIndex, effectID, 0);
    selectedEffect = chainIndex * 1000 + effectIndex;
    [self updateWindow];
    [self showCustomViewForEffectInChain:chainIndex atIndex:effectIndex];
}

- (void)insertEffect:(id)sender
{
    int tag = [sender tag];
    int chainIndex = tag / 1000000;
    int effectIndex = (tag / 1000) % 1000;
    int effectID = tag % 1000;
    MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(busIndex);
    if (chainIndex < 0 || chainIndex > ip->nchains)
        return;  //  This cannot happen
    MDAudioChangeEffect(busIndex, chainIndex, effectIndex, effectID, 1);
    selectedEffect = chainIndex * 1000 + effectIndex;
    [self updateWindow];
    [self showCustomViewForEffectInChain:chainIndex atIndex:effectIndex];
}

- (void)removeEffect:(id)sender
{
    int i, n;
    int tag = [sender tag];
    int chainIndex = tag / 1000000;
    int effectIndex = (tag / 1000) % 1000;
    MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(busIndex);
    if (chainIndex < 0 || chainIndex > ip->nchains)
        return;  //  This cannot happen
    MDAudioRemoveEffect(busIndex, chainIndex, effectIndex);
    if (selectedEffect / 1000 == chainIndex) {
        if (effectIndex == selectedEffect % 1000) {
            /*  Select the nearest effect on the same chain  */
            if (effectIndex == ip->chains[chainIndex].neffects) {
                /*  The view should be updated  */
                if (effectIndex == 0)
                    selectedEffect = -1;  /*  No selection  */
                /*  TODO: update the view  */
            }
        } else if (effectIndex < selectedEffect % 1000) {
            /*  Decrement the selected effect index (pointing to the same effect) */
            selectedEffect--;
        }
    }
    n = ip->chains[chainIndex].neffects;
    for (i = 0; i < 3; i++) {
        id view = [self viewWithTag:chainIndex * 1000 + kAudioEffectPanelEffectBaseTag + 1 + n * 3 + i];
        [view removeFromSuperview];
    }
    [self updateWindow];
    if (selectedEffect < 0) {
        chainIndex = -1;
        effectIndex = 0;
    } else {
        chainIndex = selectedEffect / 1000;
        effectIndex = selectedEffect % 1000;
    }
    [self showCustomViewForEffectInChain:chainIndex atIndex:effectIndex];
}

#if 0
#pragma mark ====== Delegate methods ======
#endif

- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition ofSubviewAt:(NSInteger)dividerIndex
{
    NSSize size = [[[self window] contentView] bounds].size;
    if (proposedPosition < 42.0f)
        return 42.0f;
    else if (proposedPosition > size.height - 48.0f)
        return size.height - 48.0f;
    else return proposedPosition;
}

@end

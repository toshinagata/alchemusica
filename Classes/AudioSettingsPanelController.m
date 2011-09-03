//
//  AudioSettingsPanelController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 10/06/13.
//  Copyright 2010-2011 Toshi Nagata. All rights reserved.
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

#import "AudioSettingsPanelController.h"
#import "NSWindowControllerAdditions.h"
#import "AUViewWindowController.h"
#import "MDHeaders.h"

/*  Tags for controls  */
/*  ...Base + 0: output, +1 ~ +8: bus 1 ~ 8  */
enum {
	kDevicePopUpBase = 100,
	kPanKnobBase = 200,
	kVolumeSliderBase = 300,
	kLeftLevelIndicatorBase = 400,
	kRightLevelIndicatorBase = 500,
	kCustomViewButtonBase = 600
};
#define kOutputTagOffset 50

@implementation AudioSettingsPanelController

static AudioSettingsPanelController *sharedAudioSettingsPanelController;

+ (void)openAudioSettingsPanel
{
	if (sharedAudioSettingsPanelController == nil) {
		sharedAudioSettingsPanelController = [[AudioSettingsPanelController alloc] initWithWindowNibName: @"AudioSettingsPanel"];
	}
	[[sharedAudioSettingsPanelController window] makeKeyAndOrderFront: nil];
}

- (void)updateDisplay
{
	int idx, i, n, isInput;
	NSMenu *menu;
	MDAudioDeviceInfo *dp;
	MDAudioMusicDeviceInfo *mp;
	
	for (idx = 0; idx < kMDAudioNumberOfStreams; idx++) {
		id view;
		int tagOffset;
		if (idx >= kMDAudioFirstIndexForOutputStream) {
			isInput = 0;
			tagOffset = idx - kMDAudioFirstIndexForOutputStream + kOutputTagOffset;
		} else {
			isInput = 1;
			tagOffset = idx;
		}
		/*  Device PopUp button  */
		view = [self viewWithTag: kDevicePopUpBase + tagOffset];
		/*  Create menu  */
		menu = [[[NSMenu alloc] initWithTitle: @""] autorelease];
		[menu addItemWithTitle: @"(none)" action: nil keyEquivalent: @""];
		[[menu itemAtIndex: 0] setTag: -1];
		[menu addItem: [NSMenuItem separatorItem]];
		for (i = 0; (dp = MDAudioDeviceInfoAtIndex(i, isInput)) != NULL; i++) {
			[menu addItemWithTitle: [NSString stringWithUTF8String: dp->name] action: nil keyEquivalent: @""];
			[[menu itemAtIndex: i + 2] setTag: i + 1];
		}
		if (isInput) {
			[menu addItem: [NSMenuItem separatorItem]];
			n = i + 3;  /*  Number of items  */
			for (i = 0; (mp = MDAudioMusicDeviceInfoAtIndex(i)) != NULL; i++) {
				[menu addItemWithTitle: [NSString stringWithUTF8String: mp->name] action: nil keyEquivalent: @""];
				[[menu itemAtIndex: i + n] setTag: i + kMDAudioMusicDeviceIndexOffset + 1];
			}
		}
		[view setMenu: menu];
		MDAudioGetIOStreamDevice(idx, &n);
		if (n < 0)
			[view selectItemAtIndex: 0];
		else
			[view selectItemWithTag: n + 1];
		if (n >= 0 || !isInput) {
			view = [self viewWithTag: kPanKnobBase + tagOffset];
			[view setEnabled: YES];
			view = [self viewWithTag: kVolumeSliderBase + tagOffset];
			[view setEnabled: YES];
			view = [self viewWithTag: kLeftLevelIndicatorBase + tagOffset];
			[view setEnabled: YES];
			view = [self viewWithTag: kRightLevelIndicatorBase + tagOffset];
			[view setEnabled: YES];
			if (isInput) {
				view = [self viewWithTag: kCustomViewButtonBase + tagOffset];
				if (n >= kMDAudioMusicDeviceIndexOffset && (mp = MDAudioMusicDeviceInfoAtIndex(n - kMDAudioMusicDeviceIndexOffset)) != NULL && mp->hasCustomView) {
					[view setEnabled: YES];
					[view setState: NSOnState];
				} else {
					[view setEnabled: NO];
					[view setState: NSOffState];
				}
			}
		} else {
			[[self viewWithTag: kPanKnobBase + tagOffset] setEnabled: NO];
			[[self viewWithTag: kVolumeSliderBase + tagOffset] setEnabled: NO];
			[[self viewWithTag: kLeftLevelIndicatorBase + tagOffset] setEnabled: NO];
			[[self viewWithTag: kRightLevelIndicatorBase + tagOffset] setEnabled: NO];
			view = [self viewWithTag: kCustomViewButtonBase + tagOffset];
			[view setEnabled: NO];
			[view setState: NSOffState];
		}
	}
}

- (void)timerCallback: (NSTimer *)timer
{
	float pan, volume, ampLeft, ampRight, peakLeft, peakRight;
	int idx;
	if (![[self window] isVisible])
		return;
	for (idx = 0; idx < kMDAudioNumberOfStreams; idx++) {
		if (idx < kMDAudioNumberOfInputStreams) {
			/*  Skip if the device is disabled  */
			int n;
			if (MDAudioGetIOStreamDevice(idx, &n) != kMDNoError || n < 0)
				continue;
		}
		if (MDAudioGetMixerBusAttributes(idx, &pan, &volume, &ampLeft, &ampRight, &peakLeft, &peakRight) == kMDNoError) {
			int tagOffset = (idx % kMDAudioFirstIndexForOutputStream) + (idx >= kMDAudioFirstIndexForOutputStream ? kOutputTagOffset : 0);
			ampLeft = (ampLeft * 1.6667) + 100.0;
			ampRight = (ampRight * 1.6667) + 100.0;
			if (ampLeft > 100.0)
				ampLeft = 100.0;
			if (ampLeft < 0.0)
				ampLeft = 0.0;
			if (ampRight > 100.0)
				ampRight = 100.0;
			if (ampRight < 0.0)
				ampRight = 0.0;
			[[self viewWithTag: kPanKnobBase + tagOffset] setFloatValue: pan * 100.0];
			[[self viewWithTag: kVolumeSliderBase + tagOffset] setFloatValue: volume * 100.0];
			[[self viewWithTag: kLeftLevelIndicatorBase + tagOffset] setFloatValue: ampLeft];
			[[self viewWithTag: kRightLevelIndicatorBase + tagOffset] setFloatValue: ampRight];
		}
	}
}

- (void)stopTimer
{
	if (timer != nil) {
		[timer invalidate];
		[timer release];
		timer = nil;
	}
}

- (IBAction)volumeSliderMoved:(id)sender
{
	int idx = [sender tag] - kVolumeSliderBase;
	if (idx >= kOutputTagOffset)
		idx += (kMDAudioFirstIndexForOutputStream - kOutputTagOffset);
	MDAudioSetMixerVolume(idx, [sender floatValue] * 0.01);
}
- (IBAction)panKnobMoved:(id)sender
{
	int idx = [sender tag] - kPanKnobBase;
	if (idx >= kOutputTagOffset)
		idx += (kMDAudioFirstIndexForOutputStream - kOutputTagOffset);
	MDAudioSetMixerPan(idx, [sender floatValue] * 0.01);
}

- (IBAction)myPopUpAction: (id)sender
{
	int idx = [sender tag] - kDevicePopUpBase;
	int dev = [[sender selectedItem] tag];
	if (dev > 0)
		dev--;
	if (idx >= kOutputTagOffset)
		idx += (kMDAudioFirstIndexForOutputStream - kOutputTagOffset);
	MDAudioSelectIOStreamDevice(idx, dev);
	[self updateDisplay];
}

- (IBAction)customViewButtonPressed: (id)sender
{
	int idx = [sender tag] - kCustomViewButtonBase;
	if (idx >= 0 && idx < kMDAudioNumberOfInputStreams) {
		int dev;
		MDAudioGetIOStreamDevice(idx, &dev);
		if (dev >= kMDAudioMusicDeviceIndexOffset) {
			MDAudioIOStreamInfo *ip;
			ip = MDAudioGetIOStreamInfoAtIndex(idx);
			if (ip != NULL && ip->unit != NULL) {
				char *name = NULL;
				id cont = [AUViewWindowController windowControllerForAudioUnit: ip->unit forceGeneric: NO delegate: nil];
				if (ip->midiControllerName != NULL)
					name = ip->midiControllerName;
				else {
					MDAudioMusicDeviceInfo *mp = MDAudioMusicDeviceInfoAtIndex(ip->deviceIndex - kMDAudioMusicDeviceIndexOffset);
					if (mp != NULL && mp->name != NULL)
						name = mp->name;
				}
				if (name != NULL)
					[[cont window] setTitle: [NSString stringWithUTF8String: name]];
			}
		}
	}
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	if (timer == nil) {
	 timer = [[NSTimer scheduledTimerWithTimeInterval: 0.1 target: self selector:@selector(timerCallback:) userInfo:nil repeats:YES] retain];
	 }
	[self updateDisplay];
}

@end

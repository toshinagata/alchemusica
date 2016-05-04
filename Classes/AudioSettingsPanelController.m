//
//  AudioSettingsPanelController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 10/06/13.
//  Copyright 2010-2016 Toshi Nagata. All rights reserved.
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
	kCustomViewButtonBase = 600,
	kBusIndexTextBase = 700
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
	[sharedAudioSettingsPanelController updateDisplay];
	[sharedAudioSettingsPanelController timerCallback:nil];
}

- (void)updateDisplay
{
	int idx, i, n, isInput;
	NSMenu *menu;
	MDAudioDeviceInfo *dp;
	MDAudioMusicDeviceInfo *mp;
	if (knobValues == nil) {
		knobValues = [[NSMutableArray arrayWithCapacity:kMDAudioNumberOfStreams] retain];
		for (idx = 0; idx < kMDAudioNumberOfStreams; idx++) {
			[knobValues addObject:[NSNumber numberWithFloat:0.0]];
		}
	}
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
			[view setEnabled: (isInput != 0)];
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
			/*  The pan slider uses 60-100 (for 0 to 0.5) and 0-40 (for 0.5 to 1.0) */
			[[self viewWithTag: kPanKnobBase + tagOffset] setFloatValue: (pan - 0.5) * 80 + (pan < 0.5 ? 100 : 0)];
			[knobValues replaceObjectAtIndex:idx withObject:[NSNumber numberWithFloat:pan]];
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
	float pan, opan;
	int idx = [sender tag] - kPanKnobBase;
	if (idx >= kOutputTagOffset)
		idx += (kMDAudioFirstIndexForOutputStream - kOutputTagOffset);
	pan = [sender floatValue];
	pan = (pan >= 50.0 ? pan - 100.0 : pan) / 80.0 + 0.5;
	opan = [[knobValues objectAtIndex:idx] floatValue];
	if (pan < 0.0 || pan > 1.0 || (opan < 0.25 && pan > 0.75) || (opan > 0.75 && pan < 0.25)) {
		/*  Do not change value  */
		[sender setFloatValue:(opan - 0.5) * 80 + (opan < 0.5 ? 100 : 0)];
		return;
	}
	[knobValues replaceObjectAtIndex:idx withObject:[NSNumber numberWithFloat:pan]];
	MDAudioSetMixerPan(idx, pan);
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
	
	//  Create bus controller list
	{
		static int sTagsToCopy[] = {
			kDevicePopUpBase, kPanKnobBase, kVolumeSliderBase,
			kLeftLevelIndicatorBase, kRightLevelIndicatorBase, kCustomViewButtonBase,
			kBusIndexTextBase,
			0  /*  This is dummy to copy the horizontal line  */
		};
		int i, count;
		NSPoint pt = [separatorLine frame].origin;
		NSRect frame = [busListView frame];
		float busHeight = frame.size.height - pt.y;
		NSLog(@"(x,y)=(%g,%g), height = %g", pt.x, pt.y, busHeight);
		frame.size.height = busHeight * kMDAudioNumberOfInputStreams;
		[busListView setFrame:frame];
		for (count = 1; count < kMDAudioNumberOfInputStreams; count++) {
			for (i = 0; i < sizeof(sTagsToCopy) / sizeof(sTagsToCopy[0]); i++) {
				NSView *view, *newview;
				NSData *data;
				NSRect vframe;
				int tag = sTagsToCopy[i];
				if (tag == 0)
					view = separatorLine;
				else
					view = [self viewWithTag:tag];
				data = [NSKeyedArchiver archivedDataWithRootObject:view];
				newview = [NSKeyedUnarchiver unarchiveObjectWithData:data];
				if (tag != 0)
					[(id)newview setTag:tag + count];
				if (tag == kBusIndexTextBase)
					[(id)newview setStringValue:[NSString stringWithFormat:@"Bus %d", count + 1]];
				vframe = [view frame];
				vframe.origin.y -= count * busHeight;
				[newview setFrame:vframe];
				[busListView addSubview:newview];
			}
		}
	}
	
	if (timer == nil) {
		timer = [[NSTimer scheduledTimerWithTimeInterval: 0.1 target: self selector:@selector(timerCallback:) userInfo:nil repeats:YES] retain];
	}
	[self updateDisplay];
}

@end

/*
 Copyright 2010-2012 Toshi Nagata.  All rights reserved.
 
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
*/

#import "RecordPanelController.h"
#import "MyDocument.h"
#import "MDHeaders.h"
#import "MyMIDISequence.h"
#import "MyAppController.h"

@implementation RecordPanelController

- (id)initWithDocument: (MyDocument *)document audio: (BOOL)audioFlag
{
    self = [super initWithWindowNibName: (audioFlag ? @"AudioRecordPanel" : @"RecordPanel")];
	myDocument = [document retain];
	isAudio = audioFlag;
    return self;
}

- (void)dealloc
{
	if (calib != NULL)
		MDCalibratorRelease(calib);
    [myDocument release];
	[info release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

static id
sAllowedExtensionsForTag(int tag)
{
	id obj;
	if (tag == 1) {
		obj = [NSArray arrayWithObjects:@"wav", nil];
	} else if (tag == 0) {
		obj = [NSArray arrayWithObjects:@"aiff", @"aif", nil];
	} else {
		obj = nil;
	}
	return obj;
}

- (void)updateDisplay
{
	MyMIDISequence *seq = [myDocument myMIDISequence];
	NSString *s;
	int32_t bar, beat, tick;
	int ival;
	MDTickType theTick;

	s = [info valueForKey: (isAudio ? MyRecordingInfoSourceAudioDeviceKey : MyRecordingInfoSourceDeviceKey)];
	if (s == nil) {
		[sourceDevicePopUp selectItemAtIndex: 0];
	} else {
		[sourceDevicePopUp selectItemWithTitle: s];
	}
	
	if (!isAudio) {
        [destinationDevicePopUp selectItemWithTitle: [info valueForKey: MyRecordingInfoDestinationDeviceKey]];
		ival = [[info valueForKey: MyRecordingInfoTargetTrackKey] intValue];
		if (ival > 0 && ival < [seq trackCount]) {
			[destinationTrackPopUp selectItemAtIndex: ival - 1];
		} else {
			[destinationTrackPopUp selectItemAtIndex: [destinationTrackPopUp numberOfItems] - 1];
		}
		ival = [[info valueForKey: MyRecordingInfoDestinationChannelKey] intValue];
		[midiChannelPopUp selectItemAtIndex: ival];
		ival = [[info valueForKey: MyRecordingInfoBarBeatFlagKey] intValue];
		[barBeatPopUp selectItemAtIndex: (ival ? 0 : 1)];
		ival = [[info valueForKey: MyRecordingInfoRecordingModeKey] intValue];
		[modePopUp selectItemAtIndex: ival];
		if (ival == 0) {
			[barBeatPopUp setEnabled: YES];
			[barBeatText setEnabled: YES];
		} else {
			[barBeatPopUp setEnabled: NO];
			[barBeatText setEnabled: NO];
		}
        ival = [[info valueForKey: MyRecordingInfoMIDITransposeKey] intValue];
        [transposeOctavePopUp selectItemAtIndex:8 - ((ival + 48) / 12)];
        [transposeNotePopUp selectItemAtIndex:((ival + 48) % 12)];
	}
	
	theTick = (MDTickType)[[info valueForKey: MyRecordingInfoStartTickKey] doubleValue];
	if (theTick >= 0 && theTick < kMDMaxTick) {
		MDCalibratorTickToMeasure(calib, theTick, &bar, &beat, &tick);
		s = [NSString stringWithFormat: @"%d:%d:%d", (int)bar, (int)beat, (int)tick];
	} else {
		s = @"----:--:----";
	}
	[startTickText setStringValue: s];

	theTick = (MDTickType)[[info valueForKey: MyRecordingInfoStopTickKey] doubleValue];
	if (theTick > 0 && theTick < kMDMaxTick) {
		MDCalibratorTickToMeasure(calib, theTick, &bar, &beat, &tick);
		s = [NSString stringWithFormat: @"%d:%d:%d", (int)bar, (int)beat, (int)tick];
	} else {
		s = @"----:--:----";
	}
	[stopTickText setStringValue: s];
	
	ival = [[info valueForKey: MyRecordingInfoStopFlagKey] intValue];
	[stopTickCheckbox setState: ival];
	if (ival) {
		[stopTickText setEnabled: YES];
	} else {
		[stopTickText setEnabled: NO];
	}

	ival = [[info valueForKey: MyRecordingInfoCountOffNumberKey] intValue];
	[barBeatText setIntValue: ival];
	
	ival = [[info valueForKey: MyRecordingInfoReplaceFlagKey] intValue];
	[overdubRadioMatrix selectCellWithTag: ival];
	
	if (isAudio) {
		NSString *locationText, *nameText;
		[audioSampleRatePopUp selectItemWithTitle: [NSString stringWithFormat: @"%.0f", [[info valueForKey: MyRecordingInfoAudioBitRateKey] floatValue]]];
		ival = [[info valueForKey: MyRecordingInfoAudioChannelFormatKey] intValue];		
		[audioChannelsPopUp selectItemAtIndex: ival];
		ival = [[info valueForKey: MyRecordingInfoAudioRecordingFormatKey] intValue];
		[audioFormatPopUp selectItemAtIndex: ival];
		locationText = [info valueForKey: MyRecordingInfoFolderNameKey];
		if (locationText == nil) {
			locationText = [[[myDocument fileURL] path] stringByDeletingLastPathComponent];
			if (locationText == nil)
				locationText = @"~/Music";
		}
		nameText = [info valueForKey: MyRecordingInfoFileNameKey];
		if (nameText == nil)
			nameText = @"";
		[audioFileLocationText setStringValue: locationText];
		[audioFileNameText setStringValue: nameText];
		if ([locationText length] > 0 && [nameText length] > 0)
			[startRecordingButton setEnabled: YES];
		else
			[startRecordingButton setEnabled: NO];
	}
}

/*
- (void)timerCallback: (NSTimer *)timer
{
	if (isAudio) {
		float volume, ampLeft, ampRight, peakLeft, peakRight;
		if (MDAudioGetInputVolumeAndAmplitudes(&volume, &ampLeft, &ampRight, &peakLeft, &peakRight) == kMDNoError) {
			[audioVolumeSlider setFloatValue: volume * 100.0];
			[audioLeftLevel setFloatValue: ampLeft * 100.0];
			[audioRightLevel setFloatValue: ampRight * 100.0];
			NSLog(@"ampLeft = %f, ampRight = %f", ampLeft, ampRight);
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
*/

- (void)reloadMIDIDeviceInfo
{
	int i, n;
	NSMenu *menu;
    NSString *str;
	char name[64];
	MyMIDISequence *seq = [myDocument myMIDISequence];

	//  Update the device information before starting the dialog
    //  This is unnecessary: device information is always updated whenever
    //  Audio/MIDI setup changes
//	MDPlayerReloadDeviceInformation();
	
	//  Initialize device popups (set device names and tags)
	[sourceDevicePopUp removeAllItems];
	menu = [sourceDevicePopUp menu];
	[[menu addItemWithTitle: @"Any MIDI device" action: nil keyEquivalent: @""] setTag: 0];
	n = MDPlayerGetNumberOfSources();
	for (i = 1; i <= n; i++) {
        id item;
		MDPlayerGetSourceName(i - 1, name, sizeof name);
		item = [menu addItemWithTitle:@"X" action: nil keyEquivalent: @""];
        str = [NSString stringWithUTF8String:name];
        [item setTitle:str];
        [item setTag:i];
	}
	
	[destinationDevicePopUp removeAllItems];
	menu = [destinationDevicePopUp menu];
	n = MDPlayerGetNumberOfDestinations();
	for (i = 0; i <= n; i++) {
		if (i == 0)
			strcpy(name, "(none)");
		else
			MDPlayerGetDestinationName(i - 1, name, sizeof name);
		[[menu addItemWithTitle: [NSString stringWithUTF8String: name] action: nil keyEquivalent: @""] setTag: i];
	}
	
	//  Add destinations for existing tracks (which may not be online now)
	n = [seq trackCount];
	for (i = 1; i < n; i++) {
		NSString *s = [seq deviceName: i];
		if (s == nil || [s isEqualToString: @""])
			continue;
		if (s != nil && [destinationDevicePopUp indexOfItemWithTitle: s] < 0)
			[[menu addItemWithTitle: s action: nil keyEquivalent: @""] setTag: 10000 + i];
	}
	
	//  Initialize track popup
	[destinationTrackPopUp removeAllItems];
	menu = [destinationTrackPopUp menu];
	n = [[myDocument myMIDISequence] trackCount];
	for (i = 1; i < n; i++) {
		[[menu addItemWithTitle: [NSString stringWithFormat: @"%d: %@", i, [[myDocument myMIDISequence] trackName: i]] action: nil keyEquivalent: @""] setTag: i];
	}
	[menu addItem: [NSMenuItem separatorItem]];
	[[menu addItemWithTitle: @"Create new track" action: nil keyEquivalent: @""] setTag: -1];
}

- (void)reloadInfoFromDocument
{
	NSString *str1, *str2;
	id obj;
	int tag;
	MyMIDISequence *seq = [myDocument myMIDISequence];

	//  In case window is not yet visible
	[self window];
	
	//  Current recordingInfo
	info = [[NSMutableDictionary dictionaryWithDictionary: [seq recordingInfo]] retain];
	
	if (!isAudio) {
		[self reloadMIDIDeviceInfo];
	}

	//  Initialize the calibrator
	{
		MDSequence *mds = [seq mySequence];
		MDTrack *track = MDSequenceGetTrack(mds, 0);
		if (calib != NULL)
			MDCalibratorRelease(calib);
		//  Tempo is not necessary (only ticks are handled here)
		calib = MDCalibratorNew(mds, track, kMDEventTimeSignature, -1);
	}
	
	[info setValue: [NSNumber numberWithBool: isAudio] forKey: MyRecordingInfoIsAudioKey];

	str1 = [[myDocument fileURL] path];
	str2 = [info valueForKey: MyRecordingInfoFileNameKey];
	obj = [info valueForKey:MyRecordingInfoAudioRecordingFormatKey];
	tag = (obj == nil ? 0 : [obj intValue]);
	obj = sAllowedExtensionsForTag(tag);
	if (str2 == nil && str1 != nil) {
		str2 = [[str1 lastPathComponent] stringByDeletingPathExtension];
		if (obj != nil)
			str2 = [str2 stringByAppendingPathExtension:[obj objectAtIndex:0]];
		[info setValue:str2 forKey:MyRecordingInfoFileNameKey];
	}
	str2 = [info valueForKey:MyRecordingInfoFolderNameKey];
	if (str2 == nil && str1 != nil) {
		str2 = [str1 stringByDeletingLastPathComponent];
		[info setValue:str2 forKey:MyRecordingInfoFolderNameKey];
	}
	
	[self updateDisplay];
}

- (void)saveInfoToDocument
{
//	NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
	MyMIDISequence *seq = [myDocument myMIDISequence];
	[seq setRecordingInfo: info];
/*	[def setValue:[[metronomeDevicePopUp selectedItem] title] forKey:MyRecordingInfoMetronomeDeviceKey];
	[def setValue:[NSNumber numberWithInt:[metronomeChannelPopUp indexOfSelectedItem]]  forKey:MyRecordingInfoMetronomeChannelKey]; */
}

- (void)midiSetupDidChange:(NSNotification *)aNotification
{
	[self reloadMIDIDeviceInfo];
	[self updateDisplay];
}

- (void)windowDidLoad
{
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(midiSetupDidChange:)
	 name:MyAppControllerMIDISetupDidChangeNotification
	 object:[NSApp delegate]];	
}

//- (void)beginSheetForWindow: (NSWindow *)parentWindow invokeStopModalWhenDone: (BOOL)flag
//{
//	NSWindow *window = [self window];
//	[self reloadInfo];
//	[self updateDisplay];
//	stopModalFlag = flag;
//	[[NSApplication sharedApplication] beginSheet: window
//		modalForWindow: parentWindow
//		modalDelegate: self
//		didEndSelector: @selector(sheetDidEnd:returnCode:contextInfo:)
//		contextInfo: nil];
//}

- (IBAction)cancelButtonPressed: (id)sender
{
    editingText = nil;
	[[NSApplication sharedApplication] endSheet: [self window] returnCode: 0];
}

- (IBAction)myPopUpAction: (id)sender
{
	id item;
	int tag, ch;
    int32_t dev;
	NSString *str;
	MyMIDISequence *seq = [myDocument myMIDISequence];

	item = [sender selectedItem];
	if (item == nil)
		return;
	tag = (int)[item tag];
	if (sender == sourceDevicePopUp) {
		str = [item title];
		if (isAudio) {
		//	[info setValue: str forKey: MyRecordingInfoSourceAudioDeviceKey];
		//	MDAudioSelectInOutDeviceAtIndices([item tag], -1);
		} else {
			[info setValue: (tag == 0 ? nil : str) forKey: MyRecordingInfoSourceDeviceKey];
		}
	} else if (sender == destinationDevicePopUp) {
		str = [item title];
		if (isAudio) {
		//	[info setValue: str forKey: MyRecordingInfoDestinationAudioDeviceKey];
		//	MDAudioSelectInOutDeviceAtIndices(-1, [item tag]);
		} else {
			[info setValue: str forKey: MyRecordingInfoDestinationDeviceKey];
            dev = MDPlayerGetDestinationNumberFromName([str UTF8String]);
            ch = 0;
            if (dev >= 0) {
                item = [midiChannelPopUp selectedItem];
                if (item != nil)
                    ch = (int)[item tag] - 1;
            }
            MDPlayerSetMIDIThruDeviceAndChannel(dev, ch);
		}
	} else if (sender == midiChannelPopUp) {
		[info setValue: [NSNumber numberWithInt: tag - 1] forKey: MyRecordingInfoDestinationChannelKey];
        if (!isAudio) {
            item = [destinationDevicePopUp selectedItem];
            if (item != nil) {
                str = [item title];
                if (str != nil) {
                    dev = MDPlayerGetDestinationNumberFromName([str UTF8String]);
                    if (dev >= 0)
                        MDPlayerSetMIDIThruDeviceAndChannel(dev, tag - 1);
                }
            }
        }
	} else if (sender == destinationTrackPopUp) {
		
		[info setValue: [NSNumber numberWithInt: (tag > 0 ? tag : -1)] forKey: MyRecordingInfoTargetTrackKey];
		//  Also modify destination device and channel if necessary
		if (tag > 0) {
			str = [seq deviceName: tag];
			if (str != nil && ![str isEqualToString: @""]) {
				[info setValue: str forKey: MyRecordingInfoDestinationDeviceKey];
			}
			ch = [seq trackChannel: tag];
			if (ch >= 0 && ch < 16)
				[info setValue: [NSNumber numberWithInt: ch] forKey: MyRecordingInfoDestinationChannelKey];
		}
	} else if (sender == modePopUp) {
		[info setValue: [NSNumber numberWithInt: tag] forKey: MyRecordingInfoRecordingModeKey];
	} else if (sender == barBeatPopUp) {
		[info setValue: [NSNumber numberWithBool: (tag == 0)] forKey: MyRecordingInfoBarBeatFlagKey];
    } else if (sender == transposeOctavePopUp || sender == transposeNotePopUp) {
        tag = (4 - [transposeOctavePopUp indexOfSelectedItem]) * 12;
        tag += [transposeNotePopUp indexOfSelectedItem];
        [info setValue: [NSNumber numberWithInt: tag] forKey: MyRecordingInfoMIDITransposeKey];
        MDPlayerSetMIDIThruTranspose(tag);
    } else if (sender == audioFormatPopUp) {
		[info setValue: [NSNumber numberWithInt: tag] forKey: MyRecordingInfoAudioRecordingFormatKey];
	} else if (sender == audioSampleRatePopUp) {
		float fval = [[sender titleOfSelectedItem] floatValue];
		[info setValue: [NSNumber numberWithFloat: fval] forKey: MyRecordingInfoAudioBitRateKey];
	} else if (sender == audioChannelsPopUp) {
		[info setValue: [NSNumber numberWithInt: tag] forKey: MyRecordingInfoAudioChannelFormatKey];
	}
	[self updateDisplay];
}

- (IBAction)startButtonPressed: (id)sender
{
    if (editingText != nil)
        [editingText sendAction:[editingText action] to:[editingText target]];
	[[NSApplication sharedApplication] endSheet: [self window] returnCode: 1];
}

- (IBAction)barBeatTextChanged:(id)sender
{
	int val = [sender intValue];
	[info setValue: [NSNumber numberWithInt: val] forKey: MyRecordingInfoCountOffNumberKey];
	[self updateDisplay];
}

- (IBAction)overdubRadioChecked:(id)sender
{
	int tag = (int)[[sender selectedCell] tag];
	[info setValue: [NSNumber numberWithBool: tag] forKey: MyRecordingInfoReplaceFlagKey];
	[self updateDisplay];
}

- (IBAction)stopCheckboxClicked:(id)sender
{
	int val = ([sender state] != NSOffState);
	[info setValue: [NSNumber numberWithBool: val] forKey: MyRecordingInfoStopFlagKey];
	[self updateDisplay];
}

/*
- (IBAction)playThruCheckboxClicked: (id)sender
{
	int val = ([sender state] != NSOffState);
	[info setValue: [NSNumber numberWithBool: val] forKey: MyRecordingInfoAudioPlayThroughKey];
	MDAudioEnablePlayThru(val);
	[self updateDisplay];
}
*/

- (IBAction)tickTextChanged:(id)sender
{
	int32_t bar, beat, tick;
	MDTickType mdTick;
	const char *s;
	s = [[sender stringValue] UTF8String];
	if (MDEventParseTickString(s, &bar, &beat, &tick) == 3) {
		mdTick = MDCalibratorMeasureToTick(calib, bar, beat, tick);
		[info setValue: [NSNumber numberWithDouble: mdTick] forKey: (sender == startTickText ? MyRecordingInfoStartTickKey : MyRecordingInfoStopTickKey)];
	}
	[self updateDisplay];
}

- (IBAction)chooseDestinationFile:(id)sender
{
	NSSavePanel *panel = [NSSavePanel savePanel];
	NSString *filename, *foldername;
	id obj;
	int tag;
	filename = [info valueForKey: MyRecordingInfoFileNameKey];
	foldername = [info valueForKey: MyRecordingInfoFolderNameKey];
	obj = [info valueForKey:MyRecordingInfoAudioRecordingFormatKey];
	tag = (obj == nil ? 0 : [obj intValue]);
	obj = sAllowedExtensionsForTag(tag);
	if (obj)
		[panel setAllowedFileTypes:obj];
    if (filename == nil) {
        NSString *ext = (obj != nil ? [obj objectAtIndex:0] : @"");
        filename = [NSString stringWithFormat: @"untitled.%@", ext];
    }
    if (foldername == nil)
        foldername = @"~/Music";
            
    [panel setDirectoryURL: [NSURL fileURLWithPath:[foldername stringByExpandingTildeInPath]]];
    [panel setNameFieldStringValue:filename];
	if ([panel runModal] == NSFileHandlingPanelOKButton) {
		foldername = [[[panel directoryURL] path] stringByAbbreviatingWithTildeInPath];
		filename = [[[panel URL] path] lastPathComponent];
		[info setValue: foldername forKey: MyRecordingInfoFolderNameKey];
		[info setValue: filename forKey: MyRecordingInfoFileNameKey];
	}
	[self updateDisplay];
}

- (IBAction)destinationTextChanged:(id)sender
{
	NSString *name;
	name = [sender stringValue];
	if (sender == audioFileLocationText) {
		// TODO: check the existence of the directory
		name = [name stringByAbbreviatingWithTildeInPath];
		[info setValue: name forKey: MyRecordingInfoFolderNameKey];
	} else {
		[info setValue: name forKey: MyRecordingInfoFileNameKey];
	}
	[self updateDisplay];
}

- (BOOL)control:(NSControl *)control textShouldBeginEditing:(NSText *)fieldEditor
{
    editingText = (NSTextField *)control;
    return YES;
}

- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor
{
    editingText = nil;
    return YES;
}

/*
- (IBAction)volumeSliderMoved:(id)sender
{
	if (isAudio) {
		MDAudioSetInputVolume([sender floatValue] * 0.01);
	}
}
*/

@end

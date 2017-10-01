//
//  MetronomeSettingsPanelController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 11/08/29.
//  Copyright 2011-2016 Toshi Nagata. All rights reserved.
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

#import "MetronomeSettingsPanelController.h"
#import "MyAppController.h"

#include "MDHeaders.h"

NSString
*MetronomeDeviceKey = @"metronome.device",
*MetronomeChannelKey = @"metronome.channel",
*MetronomeNote1Key = @"metronome.note1",
*MetronomeNote2Key = @"metronome.note2",
*MetronomeVelocity1Key = @"metronome.velocity1",
*MetronomeVelocity2Key = @"metronome.velocity2",
*MetronomeEnableWhenPlayKey = @"metronome.enableWhenPlay",
*MetronomeEnableWhenRecordKey = @"metronome.enableWhenRecord";

static id sharedMetronomeSettingsPanelController;

@implementation MetronomeSettingsPanelController

+ (void)initializeMetronomeSettings
{
	/*  Initialize the global metronome settings  */
	id obj;
	obj = MyAppCallback_getObjectGlobalSettings(MetronomeDeviceKey);
	if (obj != nil)
		gMetronomeInfo.dev = MDPlayerGetDestinationNumberFromName([obj UTF8String]);
	else gMetronomeInfo.dev = -1;
	obj = MyAppCallback_getObjectGlobalSettings(MetronomeChannelKey);
	if (obj == nil) {
		obj = [NSNumber numberWithInt:0];
		MyAppCallback_setObjectGlobalSettings(MetronomeChannelKey, obj);
	}
	gMetronomeInfo.channel = [obj intValue] % 16;
	obj = MyAppCallback_getObjectGlobalSettings(MetronomeNote1Key);
	if (obj == nil) {
		obj = [NSNumber numberWithInt:64];
		MyAppCallback_setObjectGlobalSettings(MetronomeNote1Key, obj);
	}
	gMetronomeInfo.note1 = [obj intValue] % 128;
	obj = MyAppCallback_getObjectGlobalSettings(MetronomeNote2Key);
	if (obj == nil) {
		obj = [NSNumber numberWithInt:60];
		MyAppCallback_setObjectGlobalSettings(MetronomeNote2Key, obj);
	}
	gMetronomeInfo.note2 = [obj intValue] % 128;
	obj = MyAppCallback_getObjectGlobalSettings(MetronomeVelocity1Key);
	if (obj == nil) {
		obj = [NSNumber numberWithInt:127];
		MyAppCallback_setObjectGlobalSettings(MetronomeVelocity1Key, obj);
	}
	gMetronomeInfo.vel1 = [obj intValue] % 128;
	obj = MyAppCallback_getObjectGlobalSettings(MetronomeVelocity2Key);
	if (obj == nil) {
		obj = [NSNumber numberWithInt:127];
		MyAppCallback_setObjectGlobalSettings(MetronomeVelocity2Key, obj);
	}
	gMetronomeInfo.vel2 = [obj intValue] % 128;
	obj = MyAppCallback_getObjectGlobalSettings(MetronomeEnableWhenPlayKey);
	if (obj == nil) {
		obj = [NSNumber numberWithBool:NO];
		MyAppCallback_setObjectGlobalSettings(MetronomeEnableWhenPlayKey, obj);
	}
	gMetronomeInfo.enableWhenPlay = [obj boolValue];
	obj = MyAppCallback_getObjectGlobalSettings(MetronomeEnableWhenRecordKey);
	if (obj == nil) {
		obj = [NSNumber numberWithBool:YES];
		MyAppCallback_setObjectGlobalSettings(MetronomeEnableWhenRecordKey, obj);
	}
	gMetronomeInfo.enableWhenRecord = [obj boolValue];
	gMetronomeInfo.duration = 80000;
	MyAppCallback_saveGlobalSettings();
}

+ (void)openMetronomeSettingsPanel
{
	if (sharedMetronomeSettingsPanelController == nil) {
		sharedMetronomeSettingsPanelController = [[MetronomeSettingsPanelController alloc] initWithWindowNibName: @"MetronomeSettingsPanel"];
	}
	[[sharedMetronomeSettingsPanelController window] makeKeyAndOrderFront: nil];
}


- (void)updateMIDIDevicePopUp
{
	NSMenu *menu;
	int i, n;
	char name[256];
	[metronomeDevicePopUp removeAllItems];
	menu = [metronomeDevicePopUp menu];
	n = MDPlayerGetNumberOfDestinations();
	for (i = 0; i <= n; i++) {
		if (i == 0)
			strcpy(name, "(none)");
		else
			MDPlayerGetDestinationName(i - 1, name, sizeof name);
		[[menu addItemWithTitle: [NSString stringWithUTF8String: name] action: nil keyEquivalent: @""] setTag: i];
	}
}

- (void)updateDisplay
{
	int i, ival;
	id obj;
	obj = MyAppCallback_getObjectGlobalSettings(MetronomeDeviceKey);
	[metronomeDevicePopUp selectItemWithTitle: obj];
	if (obj)
		gMetronomeInfo.dev = MDPlayerGetDestinationNumberFromName([obj UTF8String]);
	else gMetronomeInfo.dev = -1;
	ival = [MyAppCallback_getObjectGlobalSettings(MetronomeChannelKey) intValue];
	[metronomeChannelPopUp selectItemAtIndex: ival];
	gMetronomeInfo.channel = ival % 16;
	for (i = 0; i < 2; i++) {
		char nname[6];
		obj = MyAppCallback_getObjectGlobalSettings(i == 0 ? MetronomeNote1Key : MetronomeNote2Key);
		if (obj == nil)
			ival = (i == 0 ? 64 : 60);
		else ival = [obj intValue];
		MDEventNoteNumberToNoteName(ival % 128, nname);
		[(i == 0 ? metronomeClick1Text : metronomeClick2Text) setStringValue: [NSString stringWithFormat: @"%s(%d)", nname, ival % 128]];
		[(i == 0 ? metronomeClick1Stepper : metronomeClick2Stepper) setIntValue: ival % 128];
		if (i == 0)
			gMetronomeInfo.note1 = ival % 128;
		else gMetronomeInfo.note2 = ival % 128;
		obj = MyAppCallback_getObjectGlobalSettings(i == 0 ? MetronomeVelocity1Key : MetronomeVelocity2Key);
		if (obj == nil)
			ival = (i == 0 ? 127 : 120);
		else ival = [obj intValue];
		[(i == 0 ? metronomeVelocity1Text : metronomeVelocity2Text) setIntValue: ival % 128];
		[(i == 0 ? metronomeVelocity1Stepper : metronomeVelocity2Stepper) setIntValue: ival % 128];
		if (i == 0)
			gMetronomeInfo.vel1 = ival % 128;
		else gMetronomeInfo.vel2 = ival % 128;
	}
	obj = MyAppCallback_getObjectGlobalSettings(MetronomeEnableWhenPlayKey);
	ival = (obj != nil && [obj boolValue]);
	gMetronomeInfo.enableWhenPlay = ival;
	[metronomeEnableWhenPlayCheck setState:(ival ? NSOnState : NSOffState)];
	obj = MyAppCallback_getObjectGlobalSettings(MetronomeEnableWhenRecordKey);
	ival = (obj != nil && [obj boolValue]);
	gMetronomeInfo.enableWhenRecord = ival;
	[metronomeEnableWhenRecordCheck setState:(ival ? NSOnState : NSOffState)];
}

- (IBAction)popUpSelected:(id)sender
{
	id item = [sender selectedItem];
	NSString *str;
	if (sender == metronomeDevicePopUp) {
		str = [item title];
		MyAppCallback_setObjectGlobalSettings(MetronomeDeviceKey, str);
	} else if (sender == metronomeChannelPopUp) {
		MyAppCallback_setObjectGlobalSettings(MetronomeChannelKey, [NSNumber numberWithInt:(int)[sender indexOfSelectedItem]]);
	}
	MyAppCallback_saveGlobalSettings();
	[self updateDisplay];
}

- (IBAction)metronomeClickTextChanged:(id)sender
{
	NSString *str;
	id key;
	int ival;
	str = [sender stringValue];
	ival = MDEventNoteNameToNoteNumber([str UTF8String]);
	if (sender == metronomeClick1Text)
		key = MetronomeNote1Key;
	else if (sender == metronomeClick2Text)
		key = MetronomeNote2Key;
	else if (sender == metronomeVelocity1Text)
		key = MetronomeVelocity1Key;
	else if (sender == metronomeVelocity2Text)
		key = MetronomeVelocity2Key;
    else return;
	MyAppCallback_setObjectGlobalSettings(key, [NSNumber numberWithInt:ival]);
	MyAppCallback_saveGlobalSettings();
	[self updateDisplay];
	MDPlayerRingMetronomeClick(NULL, 0, (key == MetronomeNote1Key || key == MetronomeVelocity1Key) ? 1 : 0);
}

- (IBAction)metronomeClickStepperMoved:(id)sender
{
	int ival;
	id key;
	ival = [sender intValue];
	if (sender == metronomeClick1Stepper)
		key = MetronomeNote1Key;
	else if (sender == metronomeClick2Stepper)
		key = MetronomeNote2Key;
	else if (sender == metronomeVelocity1Stepper)
		key = MetronomeVelocity1Key;
	else if (sender == metronomeVelocity2Stepper)
		key = MetronomeVelocity2Key;
    else return;
	MyAppCallback_setObjectGlobalSettings(key, [NSNumber numberWithInt:ival]);
	MyAppCallback_saveGlobalSettings();
	[self updateDisplay];
	MDPlayerRingMetronomeClick(NULL, 0, (key == MetronomeNote1Key || key == MetronomeVelocity1Key) ? 1 : 0);
}

- (IBAction)checkBoxPressed:(id)sender
{
	int state = [sender state];
	MyAppCallback_setObjectGlobalSettings((sender == metronomeEnableWhenPlayCheck ? MetronomeEnableWhenPlayKey : MetronomeEnableWhenRecordKey), [NSNumber numberWithBool:(state == NSOnState)]);
	MyAppCallback_saveGlobalSettings();
	[self updateDisplay];
}

- (void)midiSetupDidChange:(NSNotification *)aNotification
{
	[self updateMIDIDevicePopUp];
	[self updateDisplay];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(midiSetupDidChange:)
	 name:MyAppControllerMIDISetupDidChangeNotification
	 object:[NSApp delegate]];	
	[self updateMIDIDevicePopUp];
	[self updateDisplay];
}

@end

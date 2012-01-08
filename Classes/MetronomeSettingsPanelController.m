//
//  MetronomeSettingsPanelController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 11/08/29.
//  Copyright 2011 Toshi Nagata. All rights reserved.
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
*MetronomeDeviceKey = @"metronomeDevice",
*MetronomeChannelKey = @"metronomeChannel",
*MetronomeNote1Key = @"metronomeNote1",
*MetronomeNote2Key = @"metronomeNote2",
*MetronomeVelocity1Key = @"metronomeVelocity1",
*MetronomeVelocity2Key = @"metronomeVelocity2",
*MetronomeEnableWhenPlayKey = @"metronomeEnableWhenPlay",
*MetronomeEnableWhenRecordKey = @"metronomeEnableWhenRecord";

static id sharedMetronomeSettingsPanelController;

@implementation MetronomeSettingsPanelController

+ (void)initializeMetronomeSettings
{
	/*  Initialize the global metronome settings  */
	id obj;
	NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
	obj = [def objectForKey:MetronomeDeviceKey];
	if (obj != nil)
		gMetronomeInfo.dev = MDPlayerGetDestinationNumberFromName([obj UTF8String]);
	else gMetronomeInfo.dev = -1;
	obj = [def objectForKey:MetronomeChannelKey];
	if (obj == nil) {
		obj = [NSNumber numberWithInt:0];
		[def setObject:obj forKey:MetronomeChannelKey];
	}
	gMetronomeInfo.channel = [obj intValue] % 16;
	obj = [def objectForKey:MetronomeNote1Key];
	if (obj == nil) {
		obj = [NSNumber numberWithInt:64];
		[def setObject:obj forKey:MetronomeNote1Key];
	}
	gMetronomeInfo.note1 = [obj intValue] % 128;
	obj = [def objectForKey:MetronomeNote2Key];
	if (obj == nil) {
		obj = [NSNumber numberWithInt:60];
		[def setObject:obj forKey:MetronomeNote2Key];
	}
	gMetronomeInfo.note2 = [obj intValue] % 128;
	obj = [def objectForKey:MetronomeVelocity1Key];
	if (obj == nil) {
		obj = [NSNumber numberWithInt:127];
		[def setObject:obj forKey:MetronomeVelocity1Key];
	}
	gMetronomeInfo.vel1 = [obj intValue] % 128;
	obj = [def objectForKey:MetronomeVelocity2Key];
	if (obj == nil) {
		obj = [NSNumber numberWithInt:127];
		[def setObject:obj forKey:MetronomeVelocity2Key];
	}
	gMetronomeInfo.vel2 = [obj intValue] % 128;
	obj = [def objectForKey:MetronomeEnableWhenPlayKey];
	if (obj == nil) {
		obj = [NSNumber numberWithBool:NO];
		[def setObject:obj forKey:MetronomeEnableWhenPlayKey];
	}
	gMetronomeInfo.enableWhenPlay = [obj boolValue];
	obj = [def objectForKey:MetronomeEnableWhenRecordKey];
	if (obj == nil) {
		obj = [NSNumber numberWithBool:YES];
		[def setObject:obj forKey:MetronomeEnableWhenRecordKey];
	}
	gMetronomeInfo.enableWhenRecord = [obj boolValue];
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
	NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
	obj = [def valueForKey:MetronomeDeviceKey];
	[metronomeDevicePopUp selectItemWithTitle: obj];
	if (obj)
		gMetronomeInfo.dev = MDPlayerGetDestinationNumberFromName([obj UTF8String]);
	else gMetronomeInfo.dev = -1;
	ival = [[def valueForKey:MetronomeChannelKey] intValue];
	[metronomeChannelPopUp selectItemAtIndex: ival];
	gMetronomeInfo.channel = ival % 16;
	for (i = 0; i < 2; i++) {
		char nname[6];
		obj = [def valueForKey:(i == 0 ? MetronomeNote1Key : MetronomeNote2Key)];
		if (obj == nil)
			ival = (i == 0 ? 64 : 60);
		else ival = [obj intValue];
		MDEventNoteNumberToNoteName(ival % 128, nname);
		[(i == 0 ? metronomeClick1Text : metronomeClick2Text) setStringValue: [NSString stringWithFormat: @"%s(%d)", nname, ival % 128]];
		[(i == 0 ? metronomeClick1Stepper : metronomeClick2Stepper) setIntValue: ival % 128];
		if (i == 0)
			gMetronomeInfo.note1 = ival % 128;
		else gMetronomeInfo.note2 = ival % 128;
		obj = [def valueForKey:(i == 0 ? MetronomeVelocity1Key : MetronomeVelocity2Key)];
		if (obj == nil)
			ival = (i == 0 ? 127 : 120);
		else ival = [obj intValue];
		[(i == 0 ? metronomeVelocity1Text : metronomeVelocity2Text) setIntValue: ival % 128];
		[(i == 0 ? metronomeVelocity1Stepper : metronomeVelocity2Stepper) setIntValue: ival % 128];
		if (i == 0)
			gMetronomeInfo.vel1 = ival % 128;
		else gMetronomeInfo.vel2 = ival % 128;
	}
	obj = [def objectForKey:MetronomeEnableWhenPlayKey];
	ival = (obj != nil && [obj boolValue]);
	gMetronomeInfo.enableWhenPlay = ival;
	[metronomeEnableWhenPlayCheck setState:(ival ? NSOnState : NSOffState)];
	obj = [def objectForKey:MetronomeEnableWhenRecordKey];
	ival = (obj != nil && [obj boolValue]);
	gMetronomeInfo.enableWhenRecord = ival;
	[metronomeEnableWhenRecordCheck setState:(ival ? NSOnState : NSOffState)];
}

- (IBAction)popUpSelected:(id)sender
{
	NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
	id item = [sender selectedItem];
	NSString *str;
	if (sender == metronomeDevicePopUp) {
		str = [item title];
		[def setValue: str forKey: MetronomeDeviceKey];
	} else if (sender == metronomeChannelPopUp) {
		[def setValue:[NSNumber numberWithInt:[sender indexOfSelectedItem]] forKey:MetronomeChannelKey];
	}
	[self updateDisplay];
}

- (IBAction)metronomeClickTextChanged:(id)sender
{
	NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
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
	[def setValue:[NSNumber numberWithInt:ival] forKey:key];
	MDPlayerRingMetronomeClick(NULL, 0, (key == MetronomeNote1Key || key == MetronomeVelocity1Key) ? 1 : 0);
	[self updateDisplay];
}

- (IBAction)metronomeClickStepperMoved:(id)sender
{
	NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
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
	[def setValue:[NSNumber numberWithInt:ival] forKey:key];
	MDPlayerRingMetronomeClick(NULL, 0, (key == MetronomeNote1Key || key == MetronomeVelocity1Key) ? 1 : 0);
	[self updateDisplay];
}

- (IBAction)checkBoxPressed:(id)sender
{
	NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
	int state = [sender state];
	[def setValue:[NSNumber numberWithBool:(state == NSOnState)] forKey:(sender == metronomeEnableWhenPlayCheck ? MetronomeEnableWhenPlayKey : MetronomeEnableWhenRecordKey)];
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

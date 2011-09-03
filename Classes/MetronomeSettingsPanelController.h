//
//  MetronomeSettingsPanelController.h
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

#import <Cocoa/Cocoa.h>

extern NSString
*MetronomeDeviceKey, // NSString; metronome MIDI device name
*MetronomeChannelKey, // int; metronome MIDI channel
*MetronomeNote1Key,  // int; metronome click 1 sound note number
*MetronomeNote2Key,  // int; metronome click 2 sound note number
*MetronomeVelocity1Key,  // int; metronome click 1 sound velocity
*MetronomeVelocity2Key,  // int; metronome click 2 sound velocity
*MetronomeEnableWhenPlayKey,
*MetronomeEnableWhenRecordKey;

@interface MetronomeSettingsPanelController : NSWindowController {
	IBOutlet NSPopUpButton *metronomeDevicePopUp;
	IBOutlet NSPopUpButton *metronomeChannelPopUp;
	IBOutlet NSTextField *metronomeClick1Text;
	IBOutlet NSStepper *metronomeClick1Stepper;
	IBOutlet NSTextField *metronomeClick2Text;
	IBOutlet NSStepper *metronomeClick2Stepper;
	IBOutlet NSTextField *metronomeVelocity1Text;
	IBOutlet NSStepper *metronomeVelocity1Stepper;
	IBOutlet NSTextField *metronomeVelocity2Text;
	IBOutlet NSStepper *metronomeVelocity2Stepper;
	IBOutlet NSButton *metronomeEnableWhenPlayCheck;
	IBOutlet NSButton *metronomeEnableWhenRecordCheck;
}
+ (void)initializeMetronomeSettings;
+ (void)openMetronomeSettingsPanel;
- (IBAction)popUpSelected:(id)sender;
- (IBAction)metronomeClickTextChanged:(id)sender;
- (IBAction)metronomeClickStepperMoved:(id)sender;
- (IBAction)checkBoxPressed:(id)sender;

@end

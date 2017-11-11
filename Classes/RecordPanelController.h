/* RecordPanelController */

/*
 Copyright 2010-2011 Toshi Nagata.  All rights reserved.
 
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
*/

#import <Cocoa/Cocoa.h>

#include "MDHeaders.h"
#import "MyMIDISequence.h"

@class MyDocument;

@interface RecordPanelController : NSWindowController
{
    IBOutlet NSPopUpButton *barBeatPopUp;
    IBOutlet NSTextField *barBeatText;
    IBOutlet NSPopUpButton *destinationDevicePopUp;
    IBOutlet NSPopUpButton *sourceDevicePopUp;
    IBOutlet NSPopUpButton *midiChannelPopUp;
    IBOutlet NSPopUpButton *modePopUp;
    IBOutlet NSMatrix *overdubRadioMatrix;
    IBOutlet NSPopUpButton *destinationTrackPopUp;
    IBOutlet NSTextField *startTickText;
    IBOutlet NSButton *stopTickCheckbox;
	IBOutlet NSButton *startRecordingButton;
    IBOutlet NSTextField *stopTickText;
	IBOutlet NSButton *playThruCheckbox;
	IBOutlet NSPopUpButton *audioFormatPopUp;
	IBOutlet NSPopUpButton *audioSampleRatePopUp;
	IBOutlet NSPopUpButton *audioChannelsPopUp;
	IBOutlet NSTextField *audioFileLocationText;
	IBOutlet NSTextField *audioFileNameText;
	IBOutlet NSSlider *audioVolumeSlider;
	IBOutlet NSLevelIndicator *audioLeftLevel;
	IBOutlet NSLevelIndicator *audioRightLevel;
    IBOutlet NSPopUpButton *transposeOctavePopUp;
    IBOutlet NSPopUpButton *transposeNotePopUp;
    
	BOOL stopModalFlag;
	BOOL isAudio;
	MyDocument *myDocument;
	MDCalibrator *calib;
	NSMutableDictionary *info;
    
    NSTextField *editingText;   /*  The editing text control  */

	NSTimer *timer;				/*  Refresh the display periodically during playing  */
}
- (id)initWithDocument: (MyDocument *)document audio: (BOOL)isAudio;
- (void)reloadInfoFromDocument;
- (void)saveInfoToDocument;
//- (void)beginSheetForWindow: (NSWindow *)parentWindow invokeStopModalWhenDone: (BOOL)flag;
- (IBAction)barBeatTextChanged:(id)sender;
- (IBAction)cancelButtonPressed:(id)sender;
- (IBAction)myPopUpAction:(id)sender;
- (IBAction)overdubRadioChecked:(id)sender;
- (IBAction)startButtonPressed:(id)sender;
- (IBAction)stopCheckboxClicked:(id)sender;
//- (IBAction)playThruCheckboxClicked:(id)sender;
- (IBAction)tickTextChanged:(id)sender;
- (IBAction)chooseDestinationFile:(id)sender;
- (IBAction)destinationTextChanged:(id)sender;
//- (IBAction)volumeSliderMoved:(id)sender;
@end

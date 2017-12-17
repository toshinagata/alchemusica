//
//  PlayingViewCotroller.h
//
//  Created by Toshi Nagata.
/*
    Copyright (c) 2000-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>
#import "MDHeaders.h"

@class MyDocument;

@interface PlayingViewController : NSObject
{
    IBOutlet id recordButton;
	IBOutlet id stopButton;
	IBOutlet id playButton;
	IBOutlet id pauseButton;
	IBOutlet id ffButton;
	IBOutlet id rewindButton;
    IBOutlet id countField;
    IBOutlet id markerPopup;
    IBOutlet id positionSlider;
    IBOutlet id timeField;
//    IBOutlet id tunePopup;
	IBOutlet id progressIndicator;
	IBOutlet id parentController;

//	int activeIndex;			/*  The active document (the selected item of tunePopup)  */
//	int status;					/*  The player status (kMDPlayer_ready, kMDPlayer_playing, kMDPlayer_suspended)  */
//	NSMutableArray *docArray;	/*  The array of MyMIDIDocuments  */
	MyDocument *myDocument;     /*  Initialized in windowDidLoad (called by parentController)  */
	NSMutableArray *tickArray;	/*  Marker ticks (the marker names are stored in markerPopup)  */
	MDCalibrator *calibrator;	/*  For time<->tick conversion  */
	MDTimeType currentTime;		/*  Current time (in microseconds, tune top = 0)  */
	MDTimeType totalTime;		/*  Total playing time (in microseconds)  */
	NSTimer *timer;				/*  Refresh the display periodically during playing  */
	BOOL isRecording;           /*  True if the record button is pressed  */
	BOOL shouldContinuePlay;	/*  Flag to continue playing after FF/Rewind/Slider actions */
	BOOL isAudioRecording;		/*  True if next recording activity is for audio  */
	int callbackCount;          /*  Increment by every call to timerCallback  */
//	NSTimer *resumeTimer;		/*  Timer to resume playing after FF/Rew/Slider actions  */
}

//+ (PlayingPanelController *)sharedPlayingPanelController;

- (IBAction)moveSlider:(id)sender;
- (IBAction)pressFFButton:(id)sender;
- (IBAction)pressPauseButton:(id)sender;
- (IBAction)pressPlayButton:(id)sender;
- (IBAction)pressRewindButton:(id)sender;
- (IBAction)pressStopButton:(id)sender;
- (IBAction)pressRecordButton:(id)sender;
- (void)recordButtonPressed: (id)sender audioFlag: (BOOL)audioFlag;

- (IBAction)selectMarker:(id)sender;
- (IBAction)tickTextEdited: (id)sender;
- (IBAction)timeTextEdited: (id)sender;

//- (IBAction)selectTune:(id)sender;
//- (void)selectTuneAtIndex:(int)index;
//- (int)refreshMIDIDocument: (MyDocument *)document;
//- (void)removeMIDIDocument: (MyDocument *)document;
- (void)timerCallback: (NSTimer *)timer;
- (void)refreshTimeDisplay;
- (void)updateMarkerList;

- (void)setCurrentTime: (MDTimeType)newTime;
- (void)setCurrentTick: (MDTickType)newTick;

//  Called from the parent windowController
- (void)windowDidLoad;

@end

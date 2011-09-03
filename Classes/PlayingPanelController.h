//
//  PlayingPanelCotroller.h
//
//  Created by Toshi Nagata.
/*
    Copyright (c) 2000-2011 Toshi Nagata. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

   1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
   2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import <Cocoa/Cocoa.h>
#import "MDHeaders.h"

@class MyDocument;

@interface PlayingPanelController : NSWindowController
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
    IBOutlet id tunePopup;
	IBOutlet id progressIndicator;

	int activeIndex;			/*  The active document (the selected item of tunePopup)  */
	int status;					/*  The player status (kMDPlayer_ready, kMDPlayer_playing, kMDPlayer_suspended)  */
	NSMutableArray *docArray;	/*  The array of MyMIDIDocuments  */
	NSMutableArray *tickArray;	/*  Marker ticks (the marker names are stored in markerPopup)  */
	MDCalibrator *calibrator;	/*  For time<->tick conversion  */
	MDTimeType currentTime;		/*  Current time (in microseconds, tune top = 0)  */
	MDTimeType totalTime;		/*  Total playing time (in microseconds)  */
	NSTimer *timer;				/*  Refresh the display periodically during playing  */
	BOOL isRecording;           /*  True if the record button is pressed  */
	BOOL shouldContinuePlay;	/*  Flag to continue playing after FF/Rewind/Slider actions */
//	NSTimer *resumeTimer;		/*  Timer to resume playing after FF/Rew/Slider actions  */
}

+ (PlayingPanelController *)sharedPlayingPanelController;
- (IBAction)moveSlider:(id)sender;
- (IBAction)pressFFButton:(id)sender;
- (IBAction)pressPauseButton:(id)sender;
- (IBAction)pressPlayButton:(id)sender;
- (IBAction)pressRewindButton:(id)sender;
- (IBAction)pressStopButton:(id)sender;
- (IBAction)pressRecordButton:(id)sender;
- (IBAction)selectMarker:(id)sender;
- (IBAction)selectTune:(id)sender;
- (void)selectTuneAtIndex:(int)index;
- (int)refreshMIDIDocument: (MyDocument *)document;
- (void)removeMIDIDocument: (MyDocument *)document;
- (void)timerCallback: (NSTimer *)timer;
- (void)refreshTimeDisplay;
@end

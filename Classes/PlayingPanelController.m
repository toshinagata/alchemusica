//
//  PlayingPanelCotroller.m
//
//  Created by Toshi Nagata.
/*
    Copyright (c) 2000-2011 Toshi Nagata. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

   1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
   2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "PlayingPanelController.h"
#import "MyDocument.h"
#import "MyMIDISequence.h"

@implementation PlayingPanelController

static PlayingPanelController *sharedPlayingPanelController = nil;

+ (PlayingPanelController *)sharedPlayingPanelController
{
	return sharedPlayingPanelController;
}

- (id)init
{
    self = [super initWithWindowNibName:@"PlayingPanel"];
	sharedPlayingPanelController = self;
	activeIndex = -1;
	status = kMDPlayer_idle;
	docArray = [[NSMutableArray allocWithZone: [self zone]] initWithCapacity: 16];
	tickArray = [[NSMutableArray allocWithZone: [self zone]] initWithCapacity: 16];
	calibrator = NULL;
	totalTime = currentTime = 0;
	timer = nil;
//	resumeTimer = nil;
//	shouldContinuePlay = NO;
	isRecording = NO;
	MDPlayerInitMIDIDevices();
	[[self window] makeKeyAndOrderFront: self];
    return self;
}

- (void)dealloc
{
	if (calibrator != NULL)
		MDCalibratorRelease(calibrator);
//	[timer autorelease];
	[tickArray release];
	[docArray release];
    [[NSNotificationCenter defaultCenter]
        removeObserver:self];
	[super dealloc];
}

- (void)windowDidLoad
{
	NSFont *font;
	[markerPopup removeAllItems];
	[tunePopup removeAllItems];
	[markerPopup setEnabled: NO];
	[tunePopup setEnabled: NO];
	font = [NSFont userFixedPitchFontOfSize: -1.0];
	[timeField setFont: font];
	[countField setFont: font];
	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(trackModified:)
		name:MyDocumentTrackModifiedNotification
		object:nil];
	[self refreshTimeDisplay];
}

- (void)refreshTimeDisplay
{
	MDPlayer *player;
	MDTickType tick;
	MDTimeType time;
	double d, slider;
	long bar, beat, count, marker, ntime;
	int hour, min, sec;
	NSString *countString, *timeString;
	
	if (activeIndex < 0) {
		currentTime = 0;
		countString = @"----:--:----";
		timeString = @"--:--:--";
		marker = -1;
		slider = 0.0;
		status = kMDPlayer_idle;
		[recordButton setEnabled: NO];
		[stopButton setEnabled: NO];
		[playButton setEnabled: NO];
		[pauseButton setEnabled: NO];
		[ffButton setEnabled: NO];
		[rewindButton setEnabled: NO];
	} else {
		MyDocument *doc = [docArray objectAtIndex: activeIndex];
		[stopButton setEnabled: YES];
		[playButton setEnabled: YES];
		[pauseButton setEnabled: YES];
		[ffButton setEnabled: YES];
		[rewindButton setEnabled: YES];
		if (status == kMDPlayer_playing) {
			player = [[doc myMIDISequence] myPlayer];
			if (player != NULL)
				currentTime = MDPlayerGetTime(player);  /*  Update the current time  */
		}

		if (MDSequenceGetIndexOfRecordingTrack([[doc myMIDISequence] mySequence]) < 0)
			[recordButton setEnabled: NO];
		else [recordButton setEnabled: YES];

	/*	[playButton hilite: (status == kMDPlayer_playing)];
		[pauseButton hilite: (status == kMDPlayer_suspended)];
		[recordButton hilite: isRecording]; */

	//	if (resumeTimer != nil)
	//		time = currentTime;		/*  During FF/Rew/Slider actions, time should come from the controls  */
	//	else
	//		time = currentTime = MDPlayerGetTime(player);
		/*  Display tick and time  */
		if (currentTime == 0) {
			time = totalTime;
			countString = @"----:--:----";
			marker = -1;
			slider = 0.0;
		} else {
			time = currentTime;
			tick = MDCalibratorTimeToTick(calibrator, time);
			MDCalibratorTickToMeasure(calibrator, tick, &bar, &beat, &count);
			countString = [NSString stringWithFormat: @"%4ld:%2ld:%4ld", bar, beat, count];
			if (totalTime > 0) {
				slider = (double)time / totalTime * 100.0;
			} else slider = 0.0;
			marker = [tickArray count];
			if (marker >= 1) {
				d = (double)tick;
				while (--marker >= 0) {
					if ([[tickArray objectAtIndex: marker] doubleValue] <= d)
						break;
				}
				if (marker < 0)
					marker = 0;
			} else marker = -1;
		}
		ntime = (long)(time / 1000000);
		hour = ntime / 3600;
		min = (ntime / 60) % 60;
		sec = ntime % 60;
		timeString = [NSString stringWithFormat: @"%02d:%02d:%02d", hour, min, sec];
		[doc postPlayPositionNotification: (status == kMDPlayer_playing ? MDCalibratorTimeToTick(calibrator, currentTime) : -1.0)];
	}
	[timeField setStringValue: timeString];
	[countField setStringValue: countString];
	[positionSlider setDoubleValue: slider];
	if (marker >= 0)
		[markerPopup selectItemAtIndex: marker];
}

/*
- (void)resumeTimerCallback: (NSTimer *)timer
{
	MDPlayer *player;
	if (activeIndex >= 0) {
		player = [[[docArray objectAtIndex: activeIndex] myMIDISequence] myPlayer];
		MDPlayerPreroll(player, MDCalibratorTimeToTick(calibrator, currentTime));
		status = kMDPlayer_suspended;
		if (shouldContinuePlay)
			[self pressPlayButton: self];
		else {
			[playButton setState: NSOffState];
			[pauseButton setState: NSOnState];
		}
	}
    [resumeTimer invalidate];
    [resumeTimer release];
	resumeTimer = nil;
	[timeField setBackgroundColor: [NSColor whiteColor]];
	shouldContinuePlay = NO;
}

- (void)setResumeTimer
{
	if (resumeTimer == nil)
		[timeField setBackgroundColor: [NSColor lightGrayColor]];
	else
		[resumeTimer invalidate];
	
	//  For better user experience, the play button is left pressed during
	//	FF/Rew/Slider action
	if (shouldContinuePlay)
		[playButton setState: NSOnState];

	resumeTimer = [[NSTimer scheduledTimerWithTimeInterval: 0.5 target: self selector:@selector(resumeTimerCallback:) userInfo:nil repeats:NO] retain];
}
*/

- (void)updateMarkerList
{
    MDPointer *pos;
    MDTrack *track;
    MDSequence *sequence;

	[markerPopup removeAllItems];
	[markerPopup setEnabled: NO];
	[tickArray removeAllObjects];
//	totalTime = currentTime = 0;

    if (activeIndex < 0)
        return;

    sequence = [[[docArray objectAtIndex: activeIndex] myMIDISequence] mySequence];
    if (sequence == NULL)
        return;

    /*  Total playing time  */
    totalTime = MDCalibratorTickToTime(calibrator, MDSequenceGetDuration(sequence));
    
    /*  The marker list  */
    track = MDSequenceGetTrack(sequence, 0);
    pos = MDPointerNew(track);
    if (pos != NULL) {
        /*  Search all the markers in the conductor track  */
        int n;
        MDEvent *ep;
        MDTickType tick;
        NSString *name;
        long length;
        n = 0;
        while ((ep = MDPointerForward(pos)) != NULL) {
            if (MDIsTextMetaEvent(ep) && MDGetCode(ep) == kMDMetaMarker) {
                tick = MDGetTick(ep);
                name = [NSString stringWithFormat: @"%09d: %s", n++, MDGetMessageConstPtr(ep, &length)];	/*  Prefix the name with a serial number to ensure uniqueness of the titles  */
                [tickArray addObject: [NSNumber numberWithDouble: (double)tick]];
                [markerPopup addItemWithTitle: name];
            }
        }
        while (--n >= 0) {
            /*  Remove the serial numbers from the menu titles, and set tag  */
            NSMenuItem *item = [markerPopup itemAtIndex: n];
            if (item) {
                [item setTitle: [[item title] substringFromIndex: 11]];
                [item setTag: n];
            }
        }
        [markerPopup setEnabled: ([markerPopup numberOfItems] > 0)];
		MDPointerRelease(pos);
    }
}

- (void)selectTuneAtIndex:(int)index
{
	MDSequence *sequence;
	MDTrack *track;
	MDStatus sts = kMDNoError;
//	MDPointer *pos;
//	MDEvent *ep;
//	MDTickType tick;
//	long length;
//	NSString *name;
//	int n;

	if (index < 0 || index >= [tunePopup numberOfItems]) {
		activeIndex = -1;
		status = kMDPlayer_idle;
		sequence = NULL;
	} else {
		[tunePopup selectItemAtIndex: index];
		if (index == activeIndex)
			return;
		if (status == kMDPlayer_playing || status == kMDPlayer_suspended)
			[self pressStopButton: self];
		status = kMDPlayer_ready;
		activeIndex = index;
		sequence = [[[docArray objectAtIndex: index] myMIDISequence] mySequence];
	}
	isRecording = NO;

	/*  Remove old information  */
	if (calibrator != NULL) {
		MDCalibratorRelease(calibrator);
		calibrator = NULL;
	}

	if (sequence != NULL) {
		track = MDSequenceGetTrack(sequence, 0);	/*  the conductor track  */
		calibrator = MDCalibratorNew(sequence, track, kMDEventTempo, -1);	/*  create a new calibrator  */
		if (calibrator != NULL)
			sts = MDCalibratorAppend(calibrator, track, kMDEventTimeSignature, -1);
		if (sts == kMDNoError)
			sts = MDCalibratorAppend(calibrator, track, kMDEventMetaText, kMDMetaMarker);
	}
    
	[self updateMarkerList];
	[self refreshTimeDisplay];
}

- (int)refreshMIDIDocument: (MyDocument *)document
{
	unsigned int n;

	n = [docArray indexOfObject: document];
	if (n == NSNotFound) {
		[docArray addObject: document];
		n = [docArray count] - 1;
		/*  Create a menu item with a dummy name that is unlikely to conflict with the existing name  */
		[[tunePopup menu] addItemWithTitle: [document tuneName] action: nil keyEquivalent: @""];
		[tunePopup setEnabled: YES];
		if (activeIndex == -1)
			[self selectTuneAtIndex: n];
	} else {
		/*  Update the item name  */
		[[tunePopup itemAtIndex: n] setTitle: [document tuneName]];
	//	if ([tunePopup indexOfSelectedItem] == n)
	//		[self selectTuneAtIndex: n];	/*  Refresh the internal information  */
	}
	return n;
}

- (void)removeMIDIDocument: (MyDocument *)document
{
	unsigned int n;
	n = [docArray indexOfObject: document];
	if (n != NSNotFound) {
		if (n == activeIndex)
			[self pressStopButton: self];
		[docArray removeObjectAtIndex: n];
		[tunePopup removeItemAtIndex: n];
		if ([tunePopup numberOfItems] == 0) {
			[tunePopup setEnabled: NO];
			[self selectTuneAtIndex: -1];
		} else {
			if (n > 0)
				n--;
			[self selectTuneAtIndex: n];
		}
	}
}

- (void)timerCallback: (NSTimer *)timer
{
	MyDocument *doc;
	MDPlayer *player;
	if (activeIndex >= 0 && status == kMDPlayer_playing) {
		doc = [docArray objectAtIndex: activeIndex];
		[self refreshTimeDisplay];
	//	[playButton hilite: YES];
		player = [[doc myMIDISequence] myPlayer];
        if (player != NULL && MDPlayerGetStatus(player) == kMDPlayer_exhausted)
			[self pressStopButton: self];
	}
}

#pragma mark ====== Action methods ======

- (void)prerollWithFeedback
{
	MDPlayer *player;
	if (activeIndex >= 0) {
		player = [[[docArray objectAtIndex: activeIndex] myMIDISequence] myPlayer];
		if (player != NULL) {
			[progressIndicator startAnimation: self];
			MDPlayerPreroll(player, MDCalibratorTimeToTick(calibrator, currentTime), 1);
			[progressIndicator stopAnimation: self];
		}
	}
}

- (void)restartAfterManualMovement
{
	if (status == kMDPlayer_suspended || shouldContinuePlay) {
		MDPlayer *player = [[[docArray objectAtIndex: activeIndex] myMIDISequence] myPlayer];
		if (shouldContinuePlay) {
			/*  Note: recording will be stopped and does not recover automatically  */
			MDPlayerJumpToTick(player, MDCalibratorTimeToTick(calibrator, currentTime));
			[self pressPlayButton: self];
		} else {
			[self prerollWithFeedback];
		}
	}
	shouldContinuePlay = NO;
}

- (IBAction)moveSlider:(id)sender
{
	if (activeIndex >= 0) {
		if (status == kMDPlayer_playing) {
			[self pressStopButton: self];
			shouldContinuePlay = YES;
		}
		currentTime = totalTime * ([sender doubleValue] / 100.0);
		[self refreshTimeDisplay];
		if ([[NSApp currentEvent] type] == NSLeftMouseUp)
			[self restartAfterManualMovement];
	}
}

- (IBAction)pressFFButton:(id)sender
{
//	MDPlayer *player;
	if (activeIndex >= 0) {
		if (status == kMDPlayer_playing) {
			[self pressStopButton: self];
			shouldContinuePlay = YES;
		}
		currentTime += 1000000;
		if (currentTime > totalTime)
			currentTime = totalTime;
		[self refreshTimeDisplay];
		if ([[NSApp currentEvent] type] == NSLeftMouseUp)
			[self restartAfterManualMovement];
	}
}

- (IBAction)pressRewindButton:(id)sender
{
	if (activeIndex >= 0) {
		if (status == kMDPlayer_playing) {
			[self pressStopButton: self];
			shouldContinuePlay = YES;
		}
		currentTime -= 1000000;
		if (currentTime < 0)
			currentTime = 0;
		[self refreshTimeDisplay];
		if ([[NSApp currentEvent] type] == NSLeftMouseUp)
			[self restartAfterManualMovement];
	}
}

- (IBAction)pressPauseButton:(id)sender
{
	MDPlayer *player;
	MyDocument *doc;
	if (activeIndex < 0)
		return;
	doc = [docArray objectAtIndex: activeIndex];
	player = [[doc myMIDISequence] myPlayer];
	if (status == kMDPlayer_playing) {
		MDPlayerSuspend(player);
		status = kMDPlayer_suspended;
		[playButton setState: NSOffState];
	} else if (status == kMDPlayer_ready) {
		/*  Jump to the "current" time, send MIDI events before that time, and wait for play  */
		[self prerollWithFeedback];
		status = kMDPlayer_suspended;	
	} else return;
	[pauseButton setState: NSOnState];
/*	[[docArray objectAtIndex: activeIndex] postPlayPositionNotification]; */
}

- (void)pressPlayButtonWithRecording:(BOOL)isRecordButton
{
	MDPlayer *player;
    MyDocument *doc;
	if (activeIndex < 0)
		return;
    doc = [docArray objectAtIndex: activeIndex];
	player = [[doc myMIDISequence] myPlayer];
	[playButton setState: NSOnState];
	if (status == kMDPlayer_playing)
		return;
	else if (status == kMDPlayer_suspended) {
		[pauseButton setState: NSOffState];
	} else if (status == kMDPlayer_ready) {
		MDPlayerJumpToTick(player, MDCalibratorTimeToTick(calibrator, currentTime));
	}
    if (isRecordButton)
        [doc startRecording];
    else
        MDPlayerStart(player);
	timer = [[NSTimer scheduledTimerWithTimeInterval: 0.1 target: self selector:@selector(timerCallback:) userInfo:nil repeats:YES] retain];
	status = kMDPlayer_playing;
}

- (IBAction)pressPlayButton:(id)sender
{
    [self pressPlayButtonWithRecording: NO];
}

- (IBAction)pressRecordButton:(id)sender
{
    [self pressPlayButtonWithRecording: YES];
}

- (IBAction)pressStopButton:(id)sender
{
	MyDocument *doc;
	MDPlayer *player;
	if (activeIndex < 0)
		return;
	doc = [docArray objectAtIndex: activeIndex];
	player = [[doc myMIDISequence] myPlayer];
	if (status == kMDPlayer_ready) {
		MDPlayerJumpToTick(player, 0);		/*  Rewind to the beginning of the tune  */
		currentTime = 0;
	} else {
		if (status == kMDPlayer_playing) {
			[timer invalidate];
			[timer release];
            timer = nil;
		}
        if (MDPlayerIsRecording(player))
            [doc finishRecording];
		MDPlayerStop(player);
	}
	status = kMDPlayer_ready;
	[self refreshTimeDisplay];
//	[doc postPlayPositionNotification];
	[playButton setState: NSOffState];
	[pauseButton setState: NSOffState];
	[recordButton setState: NSOffState];
//	[doc postStopPlayingNotification];
}

- (IBAction)selectMarker:(id)sender
{
	MDPlayer *player;
	int index;
	MDTickType tick;
	if (activeIndex >= 0) {
		player = [[[docArray objectAtIndex: activeIndex] myMIDISequence] myPlayer];
		index = [sender indexOfSelectedItem];
		if (index >= 0 && index < [tickArray count]) {
			if (status == kMDPlayer_playing) {
				shouldContinuePlay = YES;
				[self pressStopButton: self];
			}
			tick = (MDTimeType)[[tickArray objectAtIndex: index] doubleValue];
			currentTime = MDCalibratorTickToTime(calibrator, tick);
			if (shouldContinuePlay)
				[self pressPlayButton: self];
			else if (status == kMDPlayer_suspended) {
				MDPlayerPreroll(player, tick, 1);
				[pauseButton setState: NSOnState];
			}
			[self refreshTimeDisplay];
			shouldContinuePlay = NO;
		}
	}
}

- (IBAction)selectTune:(id)sender
{
	[self selectTuneAtIndex: [tunePopup indexOfSelectedItem]];
}

#pragma mark ====== Notification Handler ======

- (void)trackModified: (NSNotification *)notification
{
    long trackNo;
    if ([docArray indexOfObject: [notification object]] != activeIndex)
        return;
	[self updateMarkerList];
    [self refreshTimeDisplay];
}

@end

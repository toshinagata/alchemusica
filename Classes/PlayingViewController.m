//
//  PlayingViewCotroller.m
//
//  Created by Toshi Nagata.
/*
    Copyright (c) 2000-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

*/

#import "PlayingViewController.h"
#import "MyDocument.h"
#import "MyMIDISequence.h"
#import "RecordPanelController.h"
#import "GraphicWindowController.h"
#import "AudioSettingsPanelController.h"

@implementation PlayingViewController

- (id)init
{
    self = [super init];
	if (self != nil) {
	//	status = kMDPlayer_idle;
	//	docArray = [[NSMutableArray allocWithZone: [self zone]] initWithCapacity: 16];
		tickArray = [[NSMutableArray allocWithZone: [self zone]] initWithCapacity: 16];
		calibrator = NULL;
		totalTime = currentTime = 0;
		timer = nil;
	//	resumeTimer = nil;
	//	shouldContinuePlay = NO;
		isRecording = NO;
	//	MDPlayerInitMIDIDevices();
//		[[self window] makeKeyAndOrderFront: self];
	}
	return self;
}

- (void)dealloc
{
	if (timer != nil) {
		[timer invalidate];
		[timer release];
		timer = nil;
	}
	if (calibrator != NULL)
		MDCalibratorRelease(calibrator);
//	[timer autorelease];
	[tickArray release];
//	[docArray release];
    [[NSNotificationCenter defaultCenter]
        removeObserver:self];
	[super dealloc];
}

- (void)windowDidLoad
{
	NSFont *font;
	MDTrack *track;
	MDSequence *sequence;
	MDStatus sts;

	if (parentController == nil) {
		NSLog(@"Internal error: parentController in PlayingViewController is not connected to any NSWindowController. Examine the nib file.");
		return;
	}

	myDocument = (MyDocument *)[parentController document];

	/*  Initialize the calibrator  */
	sequence = [[myDocument myMIDISequence] mySequence];
	track = MDSequenceGetTrack(sequence, 0);	/*  the conductor track  */
	calibrator = MDCalibratorNew(sequence, track, kMDEventTempo, -1);	/*  create a new calibrator  */
    if (calibrator == NULL) {
        NSLog(@"Internal error: cannot allocate calibrator for PlayingViewController");
        return;
    }
    sts = MDCalibratorAppend(calibrator, track, kMDEventTimeSignature, -1);
	if (sts == kMDNoError)
		sts = MDCalibratorAppend(calibrator, track, kMDEventMetaText, kMDMetaMarker);

	[markerPopup removeAllItems];
//	[tunePopup removeAllItems];
	[markerPopup setEnabled: NO];
//	[tunePopup setEnabled: NO];
	font = [NSFont userFixedPitchFontOfSize: 10.0f];
	[timeField setFont: font];
	[countField setFont: font];
	[[NSNotificationCenter defaultCenter]
		addObserver: self
		selector: @selector(trackModified:)
		name: MyDocumentTrackModifiedNotification
		object: myDocument];
	[[NSNotificationCenter defaultCenter]
	 addObserver: self
	 selector: @selector(trackInserted:)
	 name: MyDocumentTrackInsertedNotification
	 object: myDocument];
	[[NSNotificationCenter defaultCenter]
	 addObserver: self
	 selector: @selector(trackDeleted:)
	 name: MyDocumentTrackDeletedNotification
	 object: myDocument];
	[self updateMarkerList];
	[self refreshTimeDisplay];
}

- (void)refreshTimeDisplay
{
	MDPlayer *player = [[myDocument myMIDISequence] myPlayer];
	MDTickType tick;
	MDTimeType time;
	double d, slider;
	int32_t bar, beat, count, marker, ntime;
	int hour, min, sec, status;
	NSString *countString, *timeString;
	BOOL playingOrRecording = NO;

	if (player == NULL) {
		currentTime = 0;
		countString = @"----:--:----";
		timeString = @"--:--:--";
		marker = -1;
		slider = 0.0;
	//	status = kMDPlayer_idle;
		[recordButton setEnabled: NO];
		[stopButton setEnabled: NO];
		[playButton setEnabled: NO];
		[pauseButton setEnabled: NO];
		[ffButton setEnabled: NO];
		[rewindButton setEnabled: NO];
	} else {
		status = MDPlayerGetStatus(player);
		[stopButton setEnabled: YES];
		[playButton setEnabled: YES];
		[pauseButton setEnabled: YES];
		[ffButton setEnabled: YES];
		[rewindButton setEnabled: YES];
		if (isRecording)
			[recordButton setState:NSOnState];
		else
			[recordButton setState:NSOffState];
		if (status == kMDPlayer_playing || status == kMDPlayer_exhausted) {
			playingOrRecording = YES;
			[playButton setState: NSOnState];
		} else [playButton setState: NSOffState];

		[pauseButton setState:(status == kMDPlayer_suspended ? NSOnState : NSOffState)];
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
			countString = [NSString stringWithFormat: @"%4d:%2d:%4d", bar, beat, count];
			if (totalTime > 0) {
				slider = (double)time / totalTime * 100.0;
			} else slider = 0.0;
			marker = (int)[tickArray count];
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
		ntime = (int32_t)(time / 1000000);
		hour = ntime / 3600;
		min = (ntime / 60) % 60;
		sec = ntime % 60;
		timeString = [NSString stringWithFormat: @"%02d:%02d:%02d", hour, min, sec];
		[myDocument postPlayPositionNotification: (playingOrRecording ? MDCalibratorTimeToTick(calibrator, currentTime) : -1.0f)];
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

    sequence = [[myDocument myMIDISequence] mySequence];
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
        int32_t length;
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
            NSMenuItem *item = [(NSPopUpButton *)markerPopup itemAtIndex: n];
            if (item) {
                [item setTitle: [[item title] substringFromIndex: 11]];
                [item setTag: n];
            }
        }
        [markerPopup setEnabled: ([markerPopup numberOfItems] > 0)];
		MDPointerRelease(pos);
    }
}

/*
- (void)selectTuneAtIndex:(int)index
{
	MDSequence *sequence;
	MDTrack *track;
	MDStatus sts = kMDNoError;
//	MDPointer *pos;
//	MDEvent *ep;
//	MDTickType tick;
//	int32_t length;
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

	//  Remove old information
	if (calibrator != NULL) {
		MDCalibratorRelease(calibrator);
		calibrator = NULL;
	}

	if (sequence != NULL) {
		track = MDSequenceGetTrack(sequence, 0);	//  the conductor track
		calibrator = MDCalibratorNew(sequence, track, kMDEventTempo, -1);	//  create a new calibrator
		if (calibrator != NULL)
			sts = MDCalibratorAppend(calibrator, track, kMDEventTimeSignature, -1);
		if (sts == kMDNoError)
			sts = MDCalibratorAppend(calibrator, track, kMDEventMetaText, kMDMetaMarker);
	}
    
	[self updateMarkerList];
	[self refreshTimeDisplay];
}
*/

/*
- (int)refreshMIDIDocument: (MyDocument *)document
{
	unsigned int n;

	n = [docArray indexOfObject: document];
	if (n == NSNotFound) {
		[docArray addObject: document];
		n = [docArray count] - 1;
		//  Create a menu item with a dummy name that is unlikely to conflict with the existing name
		[[tunePopup menu] addItemWithTitle: [document tuneName] action: nil keyEquivalent: @""];
		[tunePopup setEnabled: YES];
		if (activeIndex == -1)
			[self selectTuneAtIndex: n];
	} else {
		//  Update the item name 
		[[tunePopup itemAtIndex: n] setTitle: [document tuneName]];
	//	if ([tunePopup indexOfSelectedItem] == n)
	//		[self selectTuneAtIndex: n];	//  Refresh the internal information
	}
	return n;
}
*/
/*
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
*/

- (void)timerCallback: (NSTimer *)timer
{
    int status;
    BOOL redrawRecordTrack = NO;
	MyMIDISequence *seq = [myDocument myMIDISequence];
	MDPlayer *player = [seq myPlayer];
	callbackCount++;
    if (player == NULL)
        return;
    status = MDPlayerGetStatus(player);
    if (status == kMDPlayer_playing) {
        currentTime = MDPlayerGetTime(player);  /*  Update the current time  */
        [self refreshTimeDisplay];
        if (isRecording) {
            NSDictionary *info = [seq recordingInfo];
            if (callbackCount % 10 == 0)
                redrawRecordTrack = YES;
            //  Check if recording should be stopped
            if ([[info valueForKey: MyRecordingInfoStopFlagKey] boolValue]) {
                MDTickType currentTick = MDCalibratorTimeToTick(calibrator, currentTime);
                if (currentTick >= [[info valueForKey: MyRecordingInfoStopTickKey] doubleValue]) {
                    //  Stop recording (but continue to play)
                    if (isAudioRecording) {
                        //  Audio data can be retrieved at this time
                        [myDocument finishAudioRecording];
                        isAudioRecording = NO;
                    } else {
                        //  MIDI data will be retrieved when the stop button is pressed
                        //  (It is a bad idea to insert a new track during playing)
                        //  At this time, only flush the buffer and put the events to
                        //  the recordTrack (in MyMIDISequence object)
                        MDPlayerStopRecording(player);
                        redrawRecordTrack = YES;
                    }
                    isRecording = NO;
                    [recordButton setState:NSOffState];
                }
            }
        }
    } else if (status == kMDPlayer_exhausted) {
        //  Player stopped playing
        [self pressStopButton: self];
    }
    if (redrawRecordTrack) {
        [seq collectRecordedEvents];
        [parentController reloadClientViews];
    }
}

#pragma mark ====== Action methods ======

- (void)setCurrentTime: (MDTimeType)newTime
{
	int status;
	MDTickType newTick, duration;
	MDPlayer *player = [[myDocument myMIDISequence] myPlayer];
	if (player == NULL || (status = MDPlayerGetStatus(player)) == kMDPlayer_playing || status == kMDPlayer_exhausted)
		return;  /*  Do nothing  */
	newTick = MDCalibratorTimeToTick(calibrator, newTime);
	duration = [[myDocument myMIDISequence] sequenceDuration];
	if (newTick > duration) {
		newTick = duration;
		newTime = MDCalibratorTickToTime(calibrator, newTick);
    } else if (newTick < 0) {
        newTick = 0;
        newTime = 0;
    }
	currentTime = newTime;
	if (status == kMDPlayer_suspended)
		[self pressStopButton: self];
	[self refreshTimeDisplay];
}

- (void)setCurrentTick: (MDTickType)newTick
{
	[self setCurrentTime: MDCalibratorTickToTime(calibrator, newTick)];
}

- (void)prerollWithFeedback
{
	MDPlayer *player;
	player = [[myDocument myMIDISequence] myPlayer];
	if (player != NULL) {
		[progressIndicator startAnimation: self];
		MDPlayerPreroll(player, MDCalibratorTimeToTick(calibrator, currentTime), 1);
		[progressIndicator stopAnimation: self];
	}
}

- (void)restartAfterManualMovement
{
	int status;
	MDPlayer *player = [[myDocument myMIDISequence] myPlayer];
	if (player == NULL)
		return;
	status = MDPlayerGetStatus(player);
	MDPlayerJumpToTick(player, MDCalibratorTimeToTick(calibrator, currentTime));
	if (status == kMDPlayer_suspended || shouldContinuePlay) {
		if (shouldContinuePlay) {
			/*  Note: recording will be stopped and does not recover automatically  */
		//	MDPlayerJumpToTick(player, MDCalibratorTimeToTick(calibrator, currentTime));
			[self pressPlayButton: self];
		} else {
			[self prerollWithFeedback];
		}
	}
	shouldContinuePlay = NO;
}

- (IBAction)moveSlider:(id)sender
{
	int status;
	MDPlayer *player = [[myDocument myMIDISequence] myPlayer];
	if (player == NULL)
		return;
	status = MDPlayerGetStatus(player);
	if (status == kMDPlayer_playing || status == kMDPlayer_exhausted) {
		[self pressStopButton: self];
		shouldContinuePlay = YES;
	}
	currentTime = totalTime * ([sender doubleValue] / 100.0);
	[self refreshTimeDisplay];
	if ([[NSApp currentEvent] type] == NSLeftMouseUp)
		[self restartAfterManualMovement];
}

- (IBAction)pressFFButton:(id)sender
{
	int status;
	MDPlayer *player = [[myDocument myMIDISequence] myPlayer];
	if (player == NULL)
		return;
	status = MDPlayerGetStatus(player);
	if (status == kMDPlayer_playing || status == kMDPlayer_exhausted) {
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

- (IBAction)pressRewindButton:(id)sender
{
	int status;
	MDPlayer *player = [[myDocument myMIDISequence] myPlayer];
	if (player == NULL)
		return;
	status = MDPlayerGetStatus(player);
	if (status == kMDPlayer_playing || status == kMDPlayer_exhausted) {
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

- (IBAction)pressPauseButton:(id)sender
{
	int status;
	MDPlayer *player = [[myDocument myMIDISequence] myPlayer];
	if (player == NULL)
		return;
	status = MDPlayerGetStatus(player);
	if (status == kMDPlayer_playing || status == kMDPlayer_exhausted) {
		MDPlayerSuspend(player);
		status = kMDPlayer_suspended;
		[playButton setState:NSOffState];
	} else if (status == kMDPlayer_ready || status == kMDPlayer_idle) {
		/*  Jump to the "current" time, send MIDI events before that time, and wait for play  */
		[self prerollWithFeedback];
		status = kMDPlayer_suspended;	
	} else return;
	[pauseButton setState:(status == kMDPlayer_suspended ? NSOnState : NSOffState)];
/*	[[docArray objectAtIndex: activeIndex] postPlayPositionNotification]; */
}

- (void)pressPlayButtonWithRecording:(BOOL)isRecordButton
{
	int status;
	MDPlayer *player = [[myDocument myMIDISequence] myPlayer];
	if (player == NULL)
		return;
	status = MDPlayerGetStatus(player);
	[playButton setState:NSOnState];
	if (status == kMDPlayer_playing || status == kMDPlayer_exhausted)
		return;
	else if (status == kMDPlayer_suspended) {
		[pauseButton setState:NSOnState];
	} else if (status == kMDPlayer_ready || status == kMDPlayer_idle) {
		MDPlayerJumpToTick(player, MDCalibratorTimeToTick(calibrator, currentTime));
	}
    if (isRecordButton) {
		BOOL flag;
        int countOffNumber;
        NSDictionary *info = [[myDocument myMIDISequence] recordingInfo];
        countOffNumber = [[info valueForKey: MyRecordingInfoCountOffNumberKey] intValue];
        if (countOffNumber > 0) {
            /*  Handle metronome count-off */
            int bar, beat, barBeatFlag;
            float timebase = [myDocument timebase];
            MDEvent *ep = MDCalibratorGetEvent(calibrator, NULL, kMDEventTimeSignature, -1);
            float tempo = MDCalibratorGetTempo(calibrator);
            barBeatFlag = [[info valueForKey: MyRecordingInfoBarBeatFlagKey] intValue];
            MDEventCalculateMetronomeBarAndBeat(ep, (int32_t)timebase, &bar, &beat);
            bar = (int)floor(bar * 60000000.0 / (tempo * timebase) + 0.5);
            beat = (int)ceil(beat * 60000000.0 / (tempo * timebase));
            if (barBeatFlag) {
                MDPlayerSetCountOffSettings(player, bar * countOffNumber, bar, beat);
            } else {
                MDPlayerSetCountOffSettings(player, beat * countOffNumber, 0, beat);
            }
        } else MDPlayerSetCountOffSettings(player, 0, 0, 0);
		if (isAudioRecording)
			flag = [myDocument startAudioRecording];
		else
			flag = [myDocument startRecording];
		if (!flag) {
			NSRunAlertPanel(@"Recording error", @"Cannot start recording", nil, nil, nil);
			return;
		}
		isRecording = YES;
		[recordButton setState:NSOnState];
    } else
        MDPlayerStart(player);

	/*  Enable timer for updating displays  */
	/*  (Add for three modes, so that display is updated during modal loop or dragging)  */
	timer = [[NSTimer allocWithZone:[self zone]] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:0.1] interval:0.1 target:self selector:@selector(timerCallback:) userInfo:nil repeats:YES];
	[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
	[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
	[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];

	callbackCount = 0;
	status = kMDPlayer_playing;
}

- (IBAction)pressPlayButton:(id)sender
{
    [self pressPlayButtonWithRecording: NO];
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    RecordPanelController *cont = (RecordPanelController *)[sheet windowController];
    NSDictionary *info;
    [cont saveInfoToDocument];
    [cont close];
    if (returnCode == 1) {
        info = [[myDocument myMIDISequence] recordingInfo];
        currentTime = MDCalibratorTickToTime(calibrator, (float)[[info valueForKey: MyRecordingInfoStartTickKey] doubleValue]);
        isAudioRecording = [[info valueForKey: MyRecordingInfoIsAudioKey] boolValue];
        [self pressPlayButtonWithRecording: YES];
    } else {
        [recordButton setState:NSOffState];
    }
    [cont release];
}

- (void)recordButtonPressed: (id)sender audioFlag: (BOOL)audioFlag
{
	RecordPanelController *controller;

    controller = [[RecordPanelController allocWithZone: [self zone]] initWithDocument: myDocument audio: audioFlag];
	[controller reloadInfoFromDocument];
	if (audioFlag)
		[AudioSettingsPanelController openAudioSettingsPanel];
	[[NSApplication sharedApplication] beginSheet: [controller window]
		modalForWindow: [parentController window]
		modalDelegate: self
		didEndSelector: @selector(sheetDidEnd:returnCode:contextInfo:)
		contextInfo: nil];
}

- (IBAction)pressRecordButton:(id)sender
{
	//  If "option" key is pressed then start audio recording
	//  (This is very ugly and needs update later)
	BOOL audioFlag = NO;
	if ([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask)
		audioFlag = YES;
	[self recordButtonPressed: sender audioFlag: audioFlag];
}

- (IBAction)pressStopButton:(id)sender
{
	int status;
	MDPlayer *player = [[myDocument myMIDISequence] myPlayer];
	if (player == NULL)
		return;
	status = MDPlayerGetStatus(player);
	if (status == kMDPlayer_ready || status == kMDPlayer_idle) {
		MDPlayerJumpToTick(player, 0);		/*  Rewind to the beginning of the tune  */
		currentTime = 0;
	} else {
		MDTimeType maxTime;
		currentTime = MDPlayerGetTime(player);
		if (timer != nil) {
			[timer invalidate];
			[timer autorelease];
            timer = nil;
		}
        MDPlayerStop(player);
        
        //  Finish recording
        //  MIDI recording may have finished before (see timerCallback:), so
        //  we need to check the presence of [myMIDISequence recordTrack]
        if ([[myDocument myMIDISequence] recordTrack] != NULL) {
            [myDocument finishRecording];
        } else if (isRecording && isAudioRecording) {
            [myDocument finishAudioRecording];
        }
        isRecording = NO;
        isAudioRecording = NO;
        [recordButton setState:NSOnState];

		/*  Limit currentTime by sequence duration  */
		maxTime = MDCalibratorTickToTime(calibrator, MDSequenceGetDuration([[myDocument myMIDISequence] mySequence]));
		if (currentTime > maxTime)
			currentTime = maxTime;
	}
	status = kMDPlayer_ready;
	[self refreshTimeDisplay];
	[playButton setState:NSOffState];
	[pauseButton setState:NSOffState];
	[recordButton setState:NSOffState];
}

- (IBAction)selectMarker:(id)sender
{
	int status;
	int index;
	MDTickType tick;
	MDPlayer *player = [[myDocument myMIDISequence] myPlayer];
	if (player == NULL)
		return;
	status = MDPlayerGetStatus(player);
	index = (int)[sender indexOfSelectedItem];
	if (index >= 0 && index < [tickArray count]) {
		if (status == kMDPlayer_playing || status == kMDPlayer_exhausted) {
			shouldContinuePlay = YES;
			[self pressStopButton: self];
		}
		tick = (MDTickType)[[tickArray objectAtIndex: index] doubleValue];
		currentTime = MDCalibratorTickToTime(calibrator, tick);
		MDPlayerJumpToTick(player, tick);
		if (shouldContinuePlay)
			[self pressPlayButton: self];
		else if (status == kMDPlayer_suspended) {
			MDPlayerPreroll(player, tick, 1);
			[pauseButton setState:NSOnState];
		}
		[self refreshTimeDisplay];
        [myDocument postPlayPositionNotification:tick];
		shouldContinuePlay = NO;
	}
}

- (IBAction)tickTextEdited: (id)sender
{
	int32_t bar, beat, subtick;
	MDTickType tick;
	if (MDEventParseTickString([[sender stringValue] UTF8String], &bar, &beat, &subtick) < 3)
		return;
	tick = MDCalibratorMeasureToTick(calibrator, bar, beat, subtick);
	[self setCurrentTick: tick];
}

- (IBAction)timeTextEdited: (id)sender
{
	int hour, min, sec;
	MDTimeType time;
	const char *s;
	int n;
	s = [[sender stringValue] UTF8String];
	n = sscanf(s, "%d%*[^-0-9]%d%*[^-0-9]%d", &hour, &min, &sec);
	switch (n) {
		case 1: hour = min = 0; break;
		case 2: hour = 0; break;
		case 3: break;
		default: return;
	}
	time = (((MDTimeType)hour * 60 + (MDTimeType)min) * 60 + (MDTimeType)sec) * 1000000;
	[self setCurrentTime: time];
}

/*
- (IBAction)selectTune:(id)sender
{
	[self selectTuneAtIndex: [tunePopup indexOfSelectedItem]];
}
*/

#pragma mark ====== Notification Handler ======

- (void)trackModified: (NSNotification *)notification
{
	[self updateMarkerList];
    [self refreshTimeDisplay];
}

- (void)trackInserted: (NSNotification *)notification
{
	MDPlayer *player = [[myDocument myMIDISequence] myPlayer];
	if (player != NULL)
		MDPlayerRefreshTrackDestinations(player);  /*  Refresh internal track list  */
	[self updateMarkerList];
    [self refreshTimeDisplay];
}

- (void)trackDeleted: (NSNotification *)notification
{
	[self trackInserted:notification];
}

@end

//
//  MyMIDISequence.h
//
//  Created by Toshi Nagata on Sun Jun 03 2001.
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
@class MDTrackObject;

enum {
	kRecordingModeCountOff = 0,
	kRecordingModeWaitForNote
};

enum {
	kAudioRecordingAIFFFormat = 0,
	kAudioRecordingWAVFormat
};

enum {
	kAudioRecordingMonoFormat = 0,
	kAudioRecordingStereoFormat
};

extern NSString
	*MyRecordingInfoSourceDeviceKey,	// NSString; MIDI device name (nil if any device is acceptable)
	*MyRecordingInfoDestinationDeviceKey, // NSString; MIDI device name
	*MyRecordingInfoSourceAudioDeviceKey, // NSString; Audio device name
	*MyRecordingInfoDestinationAudioDeviceKey, // NSString; Audio device name
	*MyRecordingInfoFolderNameKey,      // NSString; destination folder name (for audio only)
	*MyRecordingInfoFileNameKey,        // NSString; destination file name (for audio only)
	*MyRecordingInfoOverwriteExistingFileFlagKey, // bool; silently overwrite existing files (for audio only)
	*MyRecordingInfoMultiFileNamesKey,  // NSMutableArray of NSString; destination file names (for multiple audio recording only)
	*MyRecordingInfoTrackSelectionsKey, // NSMutableArray of MDPointSetObjects; representing track selections (for multiple audio recording only)
	*MyRecordingInfoIsAudioKey,         // bool; is audio recording?
	*MyRecordingInfoAudioPlayThroughKey, // bool; audio play through?
	*MyRecordingInfoDestinationChannelKey, // int; MIDI channel (0..15; 16 if incoming channel is to be kept)
	*MyRecordingInfoTargetTrackKey,     // int; track number (-1 if new track is to be created)
	*MyRecordingInfoReplaceFlagKey,     // bool; replace (YES) or overdub (NO)
	*MyRecordingInfoStartTickKey,       // double; start tick
	*MyRecordingInfoStopTickKey,        // double; stop tick
	*MyRecordingInfoStopFlagKey,        // bool; if YES then stop recording at stoptick
	*MyRecordingInfoRecordingModeKey,   // int; kRecordingMode{CountOff, WaitForNote}
	*MyRecordingInfoCountOffNumberKey,  // int; count off number
	*MyRecordingInfoBarBeatFlagKey,     // bool; countOffNumber is bar (YES) or beat (NO)
	*MyRecordingInfoAudioRecordingFormatKey, // int; kAudioRecording{AIFF,WAV}Format
	*MyRecordingInfoAudioBitRateKey,    // float; audio bit rate
	*MyRecordingInfoAudioChannelFormatKey; // int; kAudioRecording{Mono,Stereo}Format

extern NSString *MyRecordingInfoFileExtensionForFormat(int format);

@interface MyMIDISequence : NSObject {
    @private
    MyDocument *	myDocument;
    MDSequence *	mySequence;
	MDPlayer *		myPlayer;
    MDTrack *		recordTrack;
	NSDictionary *  recordingInfo;
	MDCalibrator *  calib;
//    MDTrack *		recordNoteOffTrack;
}

- (id)init;
- (id)initWithDocument:(MyDocument *)document;
- (MyDocument *)myDocument;
- (MDSequence *)mySequence;
- (MDTrack *)getTrackAtIndex: (int)index;
- (long)lookUpTrack:(MDTrack *)track;
- (long)trackCount;
- (MDTickType)sequenceDuration;
//- (void)updateTrackName:(long)index;
- (NSString *)trackName:(long)index;
- (NSString *)deviceName:(long)index;
- (int)trackChannel:(long)index;
- (MDTrackAttribute)trackAttributeAtIndex: (long)index;
- (void)setTrackAttribute: (MDTrackAttribute)attribute atIndex: (long)index;

- (MDCalibrator *)sharedCalibrator;

- (NSDictionary *)recordingInfo;
- (void)setRecordingInfo: (NSDictionary *)anInfo;

- (MDStatus)readSMFFromFile:(NSString *)fileName withCallback: (MDSequenceCallback)callback andData: (void *)data;
- (MDStatus)writeSMFToFile:(NSString *)fileName withCallback: (MDSequenceCallback)callback andData: (void *)data;

- (MDPlayer *)myPlayer;
//- (id)startPlay:(id)sender;
//- (id)stopPlay:(id)sender;
- (BOOL)isPlaying;
- (float)playingTime;
//- (float)playingBeat;

- (MDStatus)startMIDIRecording;
- (long)collectRecordedEvents;
- (MDTrackObject *)finishMIDIRecording;
- (MDTrack *)recordTrack;
- (MDStatus)startAudioRecordingWithName: (NSString *)filename;
- (MDStatus)finishAudioRecordingByMIDISequence;

//- (MDStatus)finishMIDIRecordingAndGetTrack: (MDTrackObject **)outTrack andTrackIndex: (long *)outIndex;

@end

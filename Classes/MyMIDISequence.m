//
//  MyMIDISequence.m
//
//  Created by Toshi Nagata on Sun Jun 03 2001.
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

#import "MyMIDISequence.h"
#import "MyDocument.h"
#import "MDObjects.h"

NSString
	*MyRecordingInfoSourceDeviceKey = @"sourceDevice",
	*MyRecordingInfoDestinationDeviceKey = @"destinationDevice",
	*MyRecordingInfoSourceAudioDeviceKey = @"sourceAudioDevice",
	*MyRecordingInfoDestinationAudioDeviceKey = @"destinationAudioDevice",
	*MyRecordingInfoFolderNameKey = @"folderName",
	*MyRecordingInfoFileNameKey = @"fileName",
	*MyRecordingInfoOverwriteExistingFileFlagKey = @"overwriteExistingFile",
	*MyRecordingInfoMultiFileNamesKey = @"multiFileNames",
	*MyRecordingInfoTrackSelectionsKey = @"trackSelections",
	*MyRecordingInfoIsAudioKey = @"isAudio",
	*MyRecordingInfoAudioPlayThroughKey = @"audioPlayThru",
	*MyRecordingInfoDestinationChannelKey = @"destinationChannel",
	*MyRecordingInfoTargetTrackKey = @"trackNumber",
	*MyRecordingInfoReplaceFlagKey = @"replaceFlag",
	*MyRecordingInfoStartTickKey = @"startTick",
	*MyRecordingInfoStopTickKey = @"stopTick",
	*MyRecordingInfoStopFlagKey = @"stopFlag",
	*MyRecordingInfoRecordingModeKey = @"recordingMode",
	*MyRecordingInfoCountOffNumberKey = @"countOffNumber",
	*MyRecordingInfoBarBeatFlagKey = @"barBeatFlag",
    *MyRecordingInfoMIDITransposeKey = @"MIDItranspose",
    *MyRecordingInfoAudioRecordingFormatKey = @"audioRecordingFormat",
	*MyRecordingInfoAudioBitRateKey = @"audioBitRate",
	*MyRecordingInfoAudioChannelFormatKey = @"audioChannelFormat";

@implementation MyMIDISequence

- (id)init {
    return [self initWithDocument:nil];
}

- (id)initWithDocument:(MyDocument *)document {
    self = [super init];
    if (self != nil) {
		MDTrack *track;
		int i;
        myDocument = document;
        mySequence = MDSequenceNew();
		if (mySequence == NULL)
			return nil;
		/*  Create conductor track and one empty track  */
		for (i = 0; i < 2; i++) {
			track = MDTrackNew();
			if (track == NULL) {
				MDSequenceRelease(mySequence);
				mySequence = NULL;
				return nil;
			}
			if (MDSequenceInsertTrack(mySequence, i, track) < 0) {
				MDTrackRelease(track);
				MDSequenceRelease(mySequence);
				mySequence = NULL;
				return nil;
			} else MDTrackRelease(track);	/* track is retained by mySequence */
		}
		myPlayer = MDPlayerNew(mySequence);
		if (myPlayer == NULL) {
			MDSequenceRelease(mySequence);
			mySequence = NULL;
			return nil;
		}
		/*  Initialize shared calibrator  */
		calib = MDCalibratorNew(mySequence, NULL, kMDEventTimeSignature, -1);
		if (calib == NULL) {
			MDSequenceRelease(mySequence);
			mySequence = NULL;
			return nil;
		}
		MDCalibratorAppend(calib, NULL, kMDEventTempo, -1);
		
		/*  Initialize MyRecordingInfo  */
		{
			recordingInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSNumber numberWithBool: NO], MyRecordingInfoIsAudioKey,
				[NSNumber numberWithBool: NO], MyRecordingInfoAudioPlayThroughKey,
				[NSNumber numberWithBool: NO], MyRecordingInfoOverwriteExistingFileFlagKey,
				[NSNumber numberWithInt: 0], MyRecordingInfoDestinationChannelKey,
				[NSNumber numberWithInt: -1], MyRecordingInfoTargetTrackKey,
				[NSNumber numberWithBool: NO], MyRecordingInfoReplaceFlagKey,
				[NSNumber numberWithDouble: 0.0], MyRecordingInfoStartTickKey,
				[NSNumber numberWithDouble: 0.0], MyRecordingInfoStopTickKey,
				[NSNumber numberWithBool: NO], MyRecordingInfoStopFlagKey,
				[NSNumber numberWithInt: 0], MyRecordingInfoRecordingModeKey,
				[NSNumber numberWithInt: 0], MyRecordingInfoCountOffNumberKey,
				[NSNumber numberWithBool: NO], MyRecordingInfoBarBeatFlagKey,
                [NSNumber numberWithInt: 0], MyRecordingInfoMIDITransposeKey,
				[NSNumber numberWithInt: kAudioRecordingAIFFFormat], MyRecordingInfoAudioRecordingFormatKey,
				[NSNumber numberWithFloat: 44100.0f], MyRecordingInfoAudioBitRateKey,
				[NSNumber numberWithInt: kAudioRecordingStereoFormat], MyRecordingInfoAudioChannelFormatKey,
				nil];
			[recordingInfo retain];
		}
    }
    return self;
}

- (void)dealloc {
	if (myPlayer != NULL)
		MDPlayerRelease(myPlayer);
	if (mySequence != NULL)
		MDSequenceRelease(mySequence);
	[recordingInfo release];
	[super dealloc];
}

#pragma mark ====== Access to sequence/track info ======

- (MyDocument *)myDocument {
    return myDocument;
}

- (MDSequence *)mySequence {
	return mySequence;
}

- (int32_t)lookUpTrack:(MDTrack *)track {
	int32_t count;
	if (mySequence != NULL) {
		for (count = MDSequenceGetNumberOfTracks(mySequence) - 1; count >= 0; count--) {
			if (MDSequenceGetTrack(mySequence, count) == track)
				return count;
		}
	}
	return -1;
}

- (MDTrack *)getTrackAtIndex: (int)index {
	if (mySequence != NULL)
		return MDSequenceGetTrack(mySequence, index);
	else return NULL;
}

- (int32_t)trackCount {
	if (mySequence != NULL)
		return MDSequenceGetNumberOfTracks(mySequence);
	else return 0;
}

- (MDTickType)sequenceDuration {
	if (mySequence != NULL) {
		MDTickType duration = MDSequenceGetDuration(mySequence);
		if (recordTrack != NULL) {
			/*  Recording  */
			MDTickType rduration = MDPlayerGetTick(myPlayer);
		/*	MDTickType rduration = MDTrackGetDuration(recordTrack); */
			if (duration < rduration)
				return rduration;
		}
		return duration;
	} else return 0;
}

/*
- (void)updateTrackName:(int32_t)index {
	if (mySequence != NULL) {
		MDTrack *track = MDSequenceGetTrack(mySequence, index);
		if (track != NULL) {
			char buf[256];
			MDTrackGuessName(track, buf, sizeof buf);
			MDTrackSetName(track, buf);
		}
	}
}
*/

- (NSString *)trackName:(int32_t)index {
    if (mySequence != NULL) {
        MDTrack *track;
		char buf[256];
		track = MDSequenceGetTrack(mySequence, index);
		if (track != NULL) {
			MDTrackGetName(track, buf, sizeof buf);
			return [NSString stringWithUTF8String:buf];
		}
	}
	return nil;
}

- (NSString *)deviceName:(int32_t)index {
    if (mySequence != NULL) {
        MDTrack *track;
		char buf[256];
		track = MDSequenceGetTrack(mySequence, index);
		if (track != NULL) {
		//	if (MDTrackGetNumberOfChannelEvents(track, -1) + MDTrackGetNumberOfSysexEvents(track) > 0) {
			//	MDTrackGuessDeviceName(track, buf, sizeof buf);
			//	int32_t dev = MDTrackGetDevice(track);
			//	if (dev < 0 || MDPlayerGetDestinationName(dev, buf, sizeof buf) != kMDNoError)
			MDTrackGetDeviceName(track, buf, sizeof buf);
			return [NSString stringWithUTF8String: buf];
		//	}
		}
	}
	return nil;
}

- (int)trackChannel:(int32_t)index {
    if (mySequence != NULL) {
        MDTrack *track = MDSequenceGetTrack(mySequence, index);
        if (track != NULL) {
//            if (MDTrackGetNumberOfChannelEvents(track, -1) > 0)
			return MDTrackGetTrackChannel(track);
        }
    }
    return -1;
}

- (MDTrackAttribute)trackAttributeAtIndex: (int32_t)index
{
	if (mySequence != NULL) {
		MDTrack *track = MDSequenceGetTrack(mySequence, index);
		if (track != NULL) {
			return MDTrackGetAttribute(track);
		}
	}
	return 0;
}

- (void)setTrackAttribute: (MDTrackAttribute)attribute atIndex: (int32_t)index
{
	if (mySequence != NULL) {
		MDTrack *track = MDSequenceGetTrack(mySequence, index);
		if (track != NULL) {
			MDTrackAttribute oldAttr = MDTrackGetAttribute(track);
			MDTrackSetAttribute(track, attribute);
			if ((oldAttr & kMDTrackAttributeSolo) != (attribute & kMDTrackAttributeSolo))
				MDSequenceUpdateMuteBySoloFlag(mySequence);
		}
	}
}

- (MDCalibrator *)sharedCalibrator
{
	return calib;
}

#pragma mark ====== File I/O ======

- (MDStatus)readSMFFromFile:(NSString *)fileName withCallback: (MDSequenceCallback)callback andData: (void *)data
{
	MDSequence *sequence;
	MDStatus sts;
	STREAM stream;
	sequence = MDSequenceNew();
    
    if (sequence == NULL) {
        return kMDErrorOutOfMemory;
    } else {
		stream = MDStreamOpenFile([fileName fileSystemRepresentation], "rb");
		if (stream != NULL) {
			sts = MDSequenceReadSMF(sequence, stream, callback, data);
			FCLOSE(stream);
		} else sts = kMDErrorCannotOpenFile;
        if (sts == kMDNoError)
            sts = MDSequenceSingleChannelMode(sequence, 1);
		if (sts != kMDNoError) {
			MDSequenceRelease(sequence);
			sequence = NULL;
		}
	}
    if (sts != kMDNoError)
        return sts;

	if (calib != NULL) {
		MDCalibratorRelease(calib);
		calib = NULL;
	}
	if (mySequence != NULL)
		MDSequenceRelease(mySequence);
	mySequence = sequence;
	if (mySequence != NULL) {
		calib = MDCalibratorNew(mySequence, NULL, kMDEventTimeSignature, -1);
		if (calib == NULL)
			sts = kMDErrorOutOfMemory;
		else
			sts = MDCalibratorAppend(calib, NULL, kMDEventTempo, -1);
		if (sts != kMDNoError)
			return sts;
		myPlayer = MDPlayerNew(mySequence);
		if (myPlayer == NULL)
			sts = kMDErrorOutOfMemory;
	}
	return sts;
}

- (MDStatus)writeSMFToFile:(NSString *)fileName withCallback: (MDSequenceCallback)callback andData: (void *)data
{
	MDStatus sts;
	STREAM stream;
	if (mySequence != NULL) {
		stream = MDStreamOpenFile([fileName fileSystemRepresentation], "wb");
		if (stream != NULL) {
			sts = MDSequenceWriteSMF(mySequence, stream, callback, data);
			FCLOSE(stream);
		} else sts = kMDErrorCannotCreateFile;
	} else sts = kMDErrorInternalError;
	return sts;
}

#pragma mark ====== Player support ======

- (MDPlayer *)myPlayer {
	return myPlayer;
}

/*
- (id)startPlay:(id)sender {
//	if (myPlayer == NULL && mySequence != NULL)
//		myPlayer = MDPlayerNew(mySequence);
	if (myPlayer != NULL)
		MDPlayerStart(myPlayer);
	return self;
}

- (id)stopPlay:(id)sender {
	if (myPlayer != NULL)
		MDPlayerStop(myPlayer);
	return self;
}
*/

- (BOOL)isPlaying {
	MDPlayerStatus status;
	if (myPlayer != NULL) {
		status = MDPlayerGetStatus(myPlayer);
	//	if (status == kMDPlayer_exhausted) {
	//		MDPlayerStop(myPlayer);
	//		status = kMDPlayer_ready;
	//	}
		return (status == kMDPlayer_playing || status == kMDPlayer_exhausted);
	}
	return NO;
}

- (float)playingTime
{
	if (myPlayer != NULL) {
		return (float)MDPlayerGetTime(myPlayer);
	} else return -1.0f;
}

//- (float)playingBeat
//{
//	if (myPlayer != NULL) {
//		return (float)MDPlayerGetTick(myPlayer) / MDSequenceGetTimebase(mySequence);
//	} else return -1.0;
//}

#pragma mark ====== MIDI/Audio Recording ======

NSString *
MyRecordingInfoFileExtensionForFormat(int format)
{
	switch (format) {
		case kAudioRecordingAIFFFormat: return @"aiff";
		case kAudioRecordingWAVFormat: return @"wav";
		default: return @"";
	}
}

- (NSDictionary *)recordingInfo
{
	return recordingInfo;
}

- (void)setRecordingInfo: (NSDictionary *)anInfo
{
	[recordingInfo autorelease];
	recordingInfo = [anInfo retain];
}

- (MDStatus)startMIDIRecording
{
	int32_t dev;
    int ch, trans;
	MDTickType tick;
	NSString *destDevice;
    if (mySequence == NULL || myPlayer == NULL)
        return kMDErrorInternalError;
    recordTrack = MDTrackNew();
	if (recordTrack == NULL)
		return kMDErrorOutOfMemory;
	if ((destDevice = [recordingInfo valueForKey: MyRecordingInfoDestinationDeviceKey]) != nil)
		dev = MDPlayerGetDestinationNumberFromName([destDevice UTF8String]);
	else dev = -1;
	ch = [[recordingInfo valueForKey: MyRecordingInfoDestinationChannelKey] intValue];
	MDPlayerSetMIDIThruDeviceAndChannel(dev, ch);
    trans = [[recordingInfo valueForKey: MyRecordingInfoMIDITransposeKey] intValue];
    MDPlayerSetMIDIThruTranspose(trans);
	tick = (MDTickType)[[recordingInfo valueForKey: MyRecordingInfoStartTickKey] doubleValue];
	if (tick >= 0 && tick < kMDMaxTick)
		MDPlayerJumpToTick(myPlayer, tick);
	if ([[recordingInfo valueForKey: MyRecordingInfoStopFlagKey] boolValue]) {
		tick = (MDTickType)[[recordingInfo valueForKey: MyRecordingInfoStopTickKey] doubleValue];
		MDPlayerSetRecordingStopTick(myPlayer, tick);
	}
    MDPlayerStartRecording(myPlayer);
    return kMDNoError;
}

- (int32_t)collectRecordedEvents
{
    MDEvent *eventBuf;
	int eventBufSize;
    MDStatus result = kMDNoError;
	int count;
    int32_t n = 0;
//    if (recordTrack == NULL || recordNoteOffTrack == NULL)
//        return kMDErrorInternalError;
	if (recordTrack == NULL)
		return -2;
	eventBuf = NULL;
	eventBufSize = 0;
    while ((count = MDPlayerGetRecordedEvents(myPlayer, &eventBuf, &eventBufSize)) > 0) {
		MDEvent *ep;
		for (ep = eventBuf; ep < eventBuf + count; ep++) {
			if (MDGetKind(ep) == kMDEventInternalNoteOff) {
				result = MDTrackMatchNoteOff(recordTrack, ep);
			} else {
				if (MDTrackAppendEvents(recordTrack, ep, 1) < 1)
					result = kMDErrorOutOfMemory;
				MDEventClear(ep);
			}
			if (result != kMDNoError)
				break;
			n++;
		}
    }
	if (result != kMDNoError)
		return -1;  /*  Error  */

	/*  Update the track duration  */
	if (n > 0) {
		MDTrackSetDuration(recordTrack, MDTrackGetLargestTick(recordTrack) + 1);
	}
	
    return n;
}

//- (MDStatus)finishMIDIRecordingAndGetTrack: (MDTrackObject **)outTrack andTrackIndex: (int32_t *)outIndex

- (MDTrackObject *)finishMIDIRecording
{
//    MDStatus result;
	int32_t n;
	MDTrackObject *trackObj;
    if (mySequence == NULL || myPlayer == NULL)
        return nil;
    MDPlayerStopRecording(myPlayer);
//    if (recordTrack == NULL || recordNoteOffTrack == NULL)
	if (recordTrack == NULL)
        return nil;
    n = [self collectRecordedEvents];
//    result = MDTrackMatchNoteOffInTrack(recordTrack, recordNoteOffTrack);

//    if (n >= 0) {
		trackObj = [[[MDTrackObject allocWithZone: [self zone]] initWithMDTrack: recordTrack] autorelease];
    //    if (outTrack != NULL)
    //        *outTrack = [[[MDTrackObject allocWithZone: [self zone]] initWithMDTrack: recordTrack] autorelease];
    //    if (outIndex != NULL)
    //        *outIndex = MDSequenceGetIndexOfRecordingTrack(mySequence);
//    } else trackObj = nil;

    MDTrackRelease(recordTrack);
	recordTrack = NULL;

//    MDTrackRelease(recordNoteOffTrack);
//    recordTrack = recordNoteOffTrack = NULL;

    return trackObj;
}

- (MDTrack *)recordTrack
{
	return recordTrack;
}

- (MDStatus)startAudioRecordingWithName: (NSString *)filename
{
//	NSString *sourceAudioDevice;
//	MDAudioDeviceID deviceID;
//	MDAudioDeviceInfo *infop;
    MDTickType tick, stopTick;
    UInt64 duration;
	MDStatus result;
//	MDAudio *myAudio;
	MDAudioFormat audioFormat;
	int fileFormat, channelFormat, mdAudioFileFormat;

    if (mySequence == NULL || myPlayer == NULL)
        return kMDErrorInternalError;
//	sourceAudioDevice = [recordingInfo valueForKey: MyRecordingInfoSourceAudioDeviceKey];
//	if (sourceAudioDevice == nil || (infop = MDAudioDeviceInfoWithName([sourceAudioDevice UTF8String], 1, NULL)) == NULL || (deviceID = infop->deviceID) == kMDAudioDeviceUnknown)
//		return kMDErrorCannotSetupAudio;
//	myAudio = MDPlayerGetAudioPlayer(myPlayer);
	tick = (MDTickType)[[recordingInfo valueForKey: MyRecordingInfoStartTickKey] doubleValue];
	if (tick >= 0 && tick < kMDMaxTick)
		MDPlayerJumpToTick(myPlayer, tick);
	tick = MDPlayerGetTick(myPlayer);
	fileFormat = [[recordingInfo valueForKey: MyRecordingInfoAudioRecordingFormatKey] intValue];
	channelFormat = [[recordingInfo valueForKey: MyRecordingInfoAudioChannelFormatKey] intValue];
	audioFormat.mSampleRate = [[recordingInfo valueForKey: MyRecordingInfoAudioBitRateKey] floatValue];
	audioFormat.mFormatID = kAudioFormatLinearPCM;
	switch (fileFormat) {
		case kAudioRecordingWAVFormat:
			audioFormat.mFormatFlags = (kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked);
			mdAudioFileFormat = kMDAudioFileWAVType;
			break;
		case kAudioRecordingAIFFFormat:
		default:
			audioFormat.mFormatFlags = (kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked);
			mdAudioFileFormat = kMDAudioFileAIFFType;
			break;
	}
	switch (channelFormat) {
		case kAudioRecordingMonoFormat: audioFormat.mChannelsPerFrame = 1; break;
		case kAudioRecordingStereoFormat: audioFormat.mChannelsPerFrame = 2; break;
		default: audioFormat.mChannelsPerFrame = 2; break;
	}
	audioFormat.mBitsPerChannel = 24;
	audioFormat.mBytesPerFrame = (audioFormat.mBitsPerChannel / 8) * audioFormat.mChannelsPerFrame;
	audioFormat.mFramesPerPacket = 1;
	audioFormat.mBytesPerPacket = audioFormat.mBytesPerFrame * audioFormat.mFramesPerPacket;
	audioFormat.mReserved = 0;
//	MDAudioFormatSetCanonical(&audioFormat, 44100, 2, YES);
	
/*	#error "Maybe need to set up audio thru device here" */

    duration = 0;
	if ([[recordingInfo valueForKey: MyRecordingInfoStopFlagKey] boolValue]) {
        MDTimeType durationTime;
		stopTick = (MDTickType)[[recordingInfo valueForKey: MyRecordingInfoStopTickKey] doubleValue];
		MDPlayerSetRecordingStopTick(myPlayer, stopTick);
        durationTime = MDCalibratorTickToTime(calib, stopTick) - MDCalibratorTickToTime(calib, tick);
        if (durationTime > 0)
            duration = ConvertMDTimeTypeToHostTime(durationTime);
	}
	
    result = MDAudioPrepareRecording([filename fileSystemRepresentation], &audioFormat, mdAudioFileFormat, duration);
    if (result != kMDNoError)
        return result;

    MDPlayerStart(myPlayer);
	MDAudioStartRecording();

    return kMDNoError;
}

- (MDStatus)finishAudioRecordingByMIDISequence
{
	if (mySequence == NULL || myPlayer == NULL)
		return kMDErrorInternalError;
	return MDAudioStopRecording();
}

@end

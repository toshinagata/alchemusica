/*
 *  MDAudio_MacOSX.c
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 08/01/06.
 *  Copyright 2008-2025 Toshi Nagata. All rights reserved.
 *

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#include "MDHeaders.h"
#include "MDAudioUtility.h"

#include <unistd.h>    /*  For getcwd()  */
#include <sys/param.h> /*  For MAXPATHLEN  */
//#include <CoreServices/CoreServices.h> /* Use Audio Component Services instead */
#include <AudioUnit/AudioComponent.h>
#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AUGraph.h>			/*  for AUNode output  */
#include <AudioToolbox/AUMIDIController.h>	/*  for routing MIDI to DLS synth */
#include <AudioToolbox/AudioConverter.h>
#include <AudioUnit/MusicDevice.h>

struct MDAudio {
	/*  Canonical audio format  */
	MDAudioFormat preferredFormat;
	
	/*  AUGraph and AUNodes  */
	AUGraph graph;
    AUNode mixer, output;
/*	AUNode synth, synth2, mixer, output, converter, splitter; */
/*	int isInputRunning; */
	int isRunning;
	
	/*  Audio Units  */
    AudioUnit mixerUnit, outputUnit;
/*	AudioUnit inputUnit, outputUnit, mixerUnit, converterUnit;
	MusicDeviceComponent musicDevice, musicDevice2;
	AUMIDIControllerRef midiCon, midiCon2; */
	
	/*  Audio/Music device infos  */
	MDArray *inputDeviceInfos, *outputDeviceInfos;
    MDArray *musicDeviceInfos, *effectDeviceInfos;
	
	/*  IO information (the mixer input/output)  */
	MDAudioIOStreamInfo ioStreamInfos[kMDAudioNumberOfStreams];
	int isAudioThruEnabled;

	/*  Feeding audio from external device  */
/*	AudioBufferList *inputBufferList; */

	/*  Recording to file  */
	ExtAudioFileRef audioFile;
	int isRecording;
    int thruEnabled;
    UInt64 recordingStartTime;
    UInt64 recordingDuration;
    
	/*  Play thru  */
/*	MDAudioDeviceInfo inputDeviceInfoCache, outputDeviceInfoCache;
	MDSampleTime firstInputTime, firstOutputTime, inToOutSampleOffset; */
	
	/*  Audio through  */
/*	MDRingBuffer *ring;
	int isAudioThruEnabled; */
};

struct MDAudio *gAudio;

#pragma mark ====== Internal Functions ======

int
MDAudioShowError(OSStatus sts, const char *file, int line)
{
	if (sts != 0)
		fprintf(stderr, "Error OSStatus = %d at %s:%d\n", (int)sts, file, line);
	return (int)sts;
}

static int
sMDAudioCompareFormat(const AudioStreamBasicDescription *format1, const AudioStreamBasicDescription *format2)
{
    if (format1->mSampleRate != format2->mSampleRate)
        return 0;
    if (format1->mFormatID != format2->mFormatID)
        return 0;
    if (format1->mFormatFlags != format2->mFormatFlags)
        return 0;
    if (format1->mBytesPerPacket != format2->mBytesPerPacket)
        return 0;
    if (format1->mFramesPerPacket != format2->mFramesPerPacket)
        return 0;
    if (format1->mBytesPerFrame != format2->mBytesPerFrame)
        return 0;
    if (format1->mChannelsPerFrame != format2->mChannelsPerFrame)
        return 0;
    if (format1->mBitsPerChannel != format2->mBitsPerChannel)
        return 0;
    return 1;
}

static void
sMDAudioReleaseMyBufferList(AudioBufferList *list)
{
	UInt32 i;
	if (list != NULL) {
		for (i = 0; i < list->mNumberBuffers; i++) {
			if (list->mBuffers[i].mData != NULL)
				free(list->mBuffers[i].mData);
		}
		free(list);
	}
}

static AudioBufferList *
sMDAudioAllocateMyBufferList(UInt32 formatFlags, UInt32 channelsPerFrame, UInt32 bytesPerFrame, UInt32 numberOfFrames)
{
	int i;
	AudioBufferList *list;
    UInt32 nchannels, nbuffers;
    if (formatFlags & kAudioFormatFlagIsNonInterleaved) {
        nbuffers = channelsPerFrame;
        nchannels = 1;
    } else {
        nbuffers = 1;
        nchannels = channelsPerFrame;
    }
	list = (AudioBufferList *)calloc(1, sizeof(AudioBufferList) + nbuffers * sizeof(AudioBuffer));
	if (list == NULL)
		return NULL;
	list->mNumberBuffers = nbuffers;
	for(i = 0; i < nbuffers; i++) {
        list->mBuffers[i].mNumberChannels = nchannels;
		list->mBuffers[i].mDataByteSize = numberOfFrames * bytesPerFrame;
		list->mBuffers[i].mData = calloc(bytesPerFrame, numberOfFrames);
		if (list->mBuffers[i].mData == NULL) {
			sMDAudioReleaseMyBufferList(list);
			return NULL;
		}
	}
	return list;
}

/*
static void
sComputeThruOffset(MDAudioIOStreamInfo *info)
{
	// The initial latency will at least be the saftey offset's of the devices + the buffer sizes
	
	info->inToOutSampleOffset = 0;
//	audio->inToOutSampleOffset = (MDSampleTime)(
//		gAudio->inputDeviceInfoCache.safetyOffset + 
//		gAudio->inputDeviceInfoCache.bufferSizeFrames + 
//		gAudio->outputDeviceInfoCache.safetyOffset + 
//		gAudio->outputDeviceInfoCache.bufferSizeFrames);
}
*/

static void
sMakeBufferSilent(AudioBufferList * ioData)
{
	UInt32 i;
	for (i = 0; i < ioData->mNumberBuffers; i++)
		memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);	
}

/*  Callback proc for input from AUHAL and write to audio-through buffer  */
static OSStatus
sMDAudioInputProc(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData)
{
	MDAudioIOStreamInfo *info = (MDAudioIOStreamInfo *)inRefCon;
	OSStatus err = noErr;
	
//	{ static int count = 99; if (++count == 100) { fprintf(stderr, "sMDAudioInputProc called at %f, ioData->mNumberBuffers = %d\n", (double)inTimeStamp->mSampleTime, (info->bufferList == NULL ? 0 : (int)info->bufferList->mNumberBuffers)); count = 0; } }

	if (info->firstInputTime < 0) {
		info->firstInputTime = inTimeStamp->mSampleTime;
	}
	
	/*  Render into audio buffer  */
	err = AudioUnitRender(info->unit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, info->bufferList);
	if (err != noErr) {
		dprintf(1, "AudioUnitRender() failed with error %d\n", (int)err);
		return err;
	}
	
    /*  Write to file (if recording enabled)  */
    if (gAudio->isRecording && info->audioFile != NULL) {
        if (info->recordingStartTime == 0)
            info->recordingStartTime = inTimeStamp->mHostTime;
        if (info->recordingDuration == 0 || inTimeStamp->mHostTime < info->recordingStartTime + info->recordingDuration) {
            err = ExtAudioFileWriteAsync(info->audioFile, inNumberFrames, info->bufferList);
            if (err != noErr) {
                dprintf(0, "ExtAudioFileWrite() failed with error %d in sMDAudioInputProc\n", (int)err);
                return err;
            }
        }
        if (!info->thruEnabled)
            sMakeBufferSilent(info->bufferList);  //  Output silence to ring buffer
    }

	/*  Write to ring buffer  */
	err = MDRingBufferStore(info->ring, info->bufferList, inNumberFrames, (MDSampleTime)inTimeStamp->mSampleTime);
	if (err != noErr) {
		dprintf(1, "MDRingBufferStore() failed with error %d\n", (int)err);
		return err;
	}

	return noErr;
}

/*  Callback proc for reading data from ring buffer and put into AUGraph input  */
static OSStatus
sMDAudioPassProc(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList * ioData)
{
	MDAudioIOStreamInfo *info = (MDAudioIOStreamInfo *)inRefCon;
	OSStatus err = noErr;
	
	if (info->firstInputTime < 0) {
		/*  The input has not arrived yet  */
		sMakeBufferSilent(ioData);
		return noErr;
	}

    //  get Delta between the devices and add it to the offset
	if (info->firstOutputTime < 0) {
		info->firstOutputTime = inTimeStamp->mSampleTime;
		info->inToOutSampleOffset = info->firstOutputTime - info->firstInputTime;
		/*  TODO: modify offset to account for the latency  */
	/*	sComputeThruOffset(audio);
		//  Is this really correct??
		if (delta < 0.0)
			info->inToOutSampleOffset -= delta;
		else
			info->inToOutSampleOffset = -delta + info->inToOutSampleOffset; */
	//	fprintf(stderr, "offset = %f\n", (double)audio->inToOutSampleOffset);
		sMakeBufferSilent(ioData);
		return noErr;
	}
	
	//  copy the data from the buffers	
	err = MDRingBufferFetch(info->ring, ioData, inNumberFrames, (MDSampleTime)inTimeStamp->mSampleTime - info->inToOutSampleOffset, false);	
	if (err != kMDRingBufferError_OK) {
		MDSampleTime bufferStartTime, bufferEndTime;
//		fprintf(stderr, "err = %d at line %d\n", (int)err, __LINE__);
		sMakeBufferSilent(ioData);
		if (err == 1 || err == -1) {
			MDRingBufferGetTimeBounds(info->ring, &bufferStartTime, &bufferEndTime);
			info->inToOutSampleOffset = inTimeStamp->mSampleTime - bufferStartTime;
//			fprintf(stderr, "buffer = (%f,%f) offset = %f\n", (double)bufferStartTime, (double)bufferEndTime, (double)audio->inToOutSampleOffset);
		} else {
			info->firstInputTime = info->firstOutputTime = -1;
		}
	}
	
	return noErr;
}

/*  Callback proc for recording to audio file  */
static OSStatus
sMDAudioRecordProc(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData)
{
	OSStatus err = noErr;
    MDAudioIOStreamInfo *info = (MDAudioIOStreamInfo *)inRefCon;
    MDSampleTime startTime, endTime, renderTime;
    
    { static int count = 0; if (++count == 100) { dprintf(3, "sMDAudioRecordProc called at %f, ioData->mNumberBuffers = %d\n", (double)inTimeStamp->mSampleTime, (int)ioData->mNumberBuffers); count = 0; } }

    /*  Sample time range to handle during this callback  */
    startTime = inTimeStamp->mSampleTime;
    endTime = startTime + inNumberFrames;
    if (info->firstInputTime < 0) {
        info->firstInputTime = inTimeStamp->mSampleTime;
    }

    /*  Fill the ring buffer until enough data is present in the ring buffer  */
    while ((renderTime = MDRingBufferEndTime(info->ring)) < endTime) {
        AudioTimeStamp timeStamp = {0};
        int i, n;
        timeStamp.mSampleTime = renderTime;
        timeStamp.mRateScalar = inTimeStamp->mRateScalar;
        timeStamp.mFlags = kAudioTimeStampSampleTimeValid | kAudioTimeStampRateScalarValid;
        n = info->bufferSizeFrames;
        for (i = 0; i < info->bufferList->mNumberBuffers; i++)
            info->bufferList->mBuffers[i].mDataByteSize = n * info->ring->bytesPerFrame;
        err = AudioUnitRender(gAudio->mixerUnit, ioActionFlags, inTimeStamp, inBusNumber, n, info->bufferList);
        if (err != noErr) {
            dprintf(1, "AudioUnitRender() failed with error %d in sMDAudioRecordProc\n", (int)err);
            return err;
        }
        /*  Write to ring buffer  */
        err = MDRingBufferStore(info->ring, info->bufferList, n, renderTime);
        if (err != noErr) {
            dprintf(1, "MDRingBufferStore() failed with error %d in sMDAudioRecordProc\n", (int)err);
            if (err < 0) {
                /*  Throw everything away from the ring buffer  */
                MDRingBufferSetTimeBounds(info->ring, startTime, startTime);
            }
            return err;
        }
    }
    
    /*  Fill ioData from the ring buffer  */
    err = MDRingBufferFetch(info->ring, ioData, inNumberFrames, startTime, false);
    if (err != noErr) {
        dprintf(1, "MDRingBufferFetch() failed with error %d in sMDAudioRecordProc\n", (int)err);
        if (err < 0) {
            /*  Throw everything away from the ring buffer  */
            MDRingBufferSetTimeBounds(info->ring, startTime, startTime);
        }
        return err;
    }

	/*  Write to file  */
	if (gAudio->isRecording && gAudio->audioFile != NULL) {
        if (gAudio->recordingStartTime == 0)
            gAudio->recordingStartTime = inTimeStamp->mHostTime;
        if (gAudio->recordingDuration == 0 || inTimeStamp->mHostTime < gAudio->recordingStartTime + gAudio->recordingDuration) {
            err = ExtAudioFileWriteAsync(gAudio->audioFile, inNumberFrames, ioData);
            if (err != noErr) {
                dprintf(0, "ExtAudioFileWrite() failed with error %d in sMDAudioRecordProc\n", (int)err);
                return err;
            }
        }
	}

	if (err != noErr) {
	//	fprintf(stderr, "sMDAudioRecordProc() failed with error %d\n", (int)err);
		return err;
	}
	
	if (!gAudio->isAudioThruEnabled || (gAudio->isRecording && !gAudio->thruEnabled))
		return 1;  /*  Discard the input data  */

	return noErr;
}

/*  Callback to send MIDI events to Music Device  */
static OSStatus
sMDAudioSendMIDIProc(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
    MDAudioIOStreamInfo *ip = (MDAudioIOStreamInfo *)inRefCon;
    int readOffset = ip->midiBufferReadOffset;
    int writeOffset = ip->midiBufferWriteOffset;
    int dataSize = (writeOffset + kMDAudioMaxMIDIBytesToSendPerDevice - readOffset) % kMDAudioMaxMIDIBytesToSendPerDevice;
    int numChannelEvents = 0;
    int readPos = readOffset;
    if ((*ioActionFlags & kAudioUnitRenderAction_PreRender) != kAudioUnitRenderAction_PreRender)
        return noErr;  /*  No action  */
    if (ip->requestFlush) {
        /*  Flush is requested: skip all unread bytes  */
        ip->requestFlush = 0;
        ip->midiBufferReadOffset = ip->midiBufferWriteOffset;
        return noErr;
    }
    while (readPos - readOffset < dataSize) {
        UInt64 timeStamp = 0;
        UInt32 offset;
        int i, len;
        unsigned char c;
        for (i = 0; i < 8; i++) {
            c = ip->midiBuffer[(readPos + i) % kMDAudioMaxMIDIBytesToSendPerDevice];
            timeStamp += (((UInt64)c) << (i * 8));
        }
        if (timeStamp > inTimeStamp->mHostTime) {
            offset = (UInt32)((double)(timeStamp - inTimeStamp->mHostTime) * (1.0 / ip->format.mSampleRate));
        } else offset = 0;
        if (offset >= inNumberFrames) {
            /*  This event is scheduled in the next or later frame, so it
             should be processed in later callback  */
            break;
        }
        len = ip->midiBuffer[(readPos + 8) % kMDAudioMaxMIDIBytesToSendPerDevice];
        c = ip->midiBuffer[(readPos + 9) % kMDAudioMaxMIDIBytesToSendPerDevice];
        if (c == 0xff || c == 0xf0) {
            /*  System Exclusive: in this case, no channel events should be scheduled
              in this callback session; otherwise, the scheduled channel events will be
              sent _after_ sending sysex. (There is no mechanism to schedule a sysex
              event to MusicDevice.)
                So, if we already scheduled any channel events, then we stop processing
             here and try to send sysex in the next session.  */
            if (numChannelEvents > 0)
                break;
            if (c == 0xff) {
                if (ip->sysexData != NULL) {
                    MusicDeviceSysEx(ip->unit, ip->sysexData, ip->sysexLength);
                    ip->sysexData = NULL;
                }
                readPos += 10; /* 8 (timeStamp) + 1 (length) + 1 (0xff) */
            } else {
                static unsigned char tempBuffer[256];
                for (i = 0; i < len; i++) {
                    tempBuffer[i] = ip->midiBuffer[(readPos + 9 + i) % kMDAudioMaxMIDIBytesToSendPerDevice];
                }
                MusicDeviceSysEx(ip->unit, tempBuffer, len);
           /*     printf("sysex %d\n", len); */
                readPos += 9 + len;
            }
        } else {
            unsigned char c2, c3;
            c2 = c3 = 0;
            if (len >= 2) {
                c2 = ip->midiBuffer[(readPos + 10) % kMDAudioMaxMIDIBytesToSendPerDevice];
                if (len >= 3) {
                    c3 = ip->midiBuffer[(readPos + 11) % kMDAudioMaxMIDIBytesToSendPerDevice];
                }
            }
            MusicDeviceMIDIEvent(ip->unit, c, c2, c3, offset);
        /*    printf("%08x %02x %02x %02x %d\n", (UInt32)ip->unit, c, c2, c3, offset); */
            readPos += 9 + len;
            numChannelEvents++;
        }
    }
    ip->midiBufferReadOffset = readPos % kMDAudioMaxMIDIBytesToSendPerDevice;
    return noErr;
}

int
MDAudioScheduleMIDIToStream(MDAudioIOStreamInfo *ip, UInt64 timeStamp, int length, unsigned char *midiData, int isSysEx)
{
    int readOffset, writeOffset, spaceSize;
    int i, length2;
    if (ip->midiBuffer == NULL)
        return 0;  /*  Not active  */
    readOffset = ip->midiBufferReadOffset;
    writeOffset = ip->midiBufferWriteOffset;
    spaceSize = (readOffset + kMDAudioMaxMIDIBytesToSendPerDevice - 1 - writeOffset) % kMDAudioMaxMIDIBytesToSendPerDevice + 1;
    if (isSysEx) {
        /*  Schedule sysex  */
        if (ip->sysexData != NULL)
            return 1;  /*  Sysex is waiting: cannot schedule until this is done  */
        ip->sysexLength = length;
        ip->sysexData = midiData;
        return 0;
    }
    length2 = length + sizeof(timeStamp) + 1;
    if (spaceSize <= length2)
        return 1;  /*  Buffer overflow  */
    for (i = 0; i < length2; i++) {
        unsigned char c;
        if (i < sizeof(timeStamp))
            c = (timeStamp >> (i * 8)) & 0xff;
        else if (i == sizeof(timeStamp))
            c = length & 0xff;  /*  Should be length <= 255  */
        else
            c = midiData[i - sizeof(timeStamp) - 1];
        ip->midiBuffer[(writeOffset + i) % kMDAudioMaxMIDIBytesToSendPerDevice] = c;
    }
    ip->midiBufferWriteOffset = (writeOffset + length2) % kMDAudioMaxMIDIBytesToSendPerDevice;
    return 0;
}

#pragma mark ====== Device information ======

static void
sMDAudioDeviceInfoDestructor(void *p)
{
	MDAudioDeviceInfo *info = (MDAudioDeviceInfo *)p;
	if (info->name != NULL)
		free(info->name);
}

static int
sMDAudioDeviceCountChannels(MDAudioDeviceID deviceID, int isInput)
{
	OSStatus err;
	UInt32 propSize, i;
	int result;
	AudioBufferList *buflist;
    AudioObjectPropertyAddress address;

    address.mSelector = kAudioDevicePropertyStreamConfiguration;
    address.mScope = (isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput);
    address.mElement = kAudioObjectPropertyElementMaster;

    err = AudioObjectGetPropertyDataSize(deviceID, &address, 0, NULL, &propSize);

//	err = AudioDeviceGetPropertyInfo(deviceID, 0, isInput, kAudioDevicePropertyStreamConfiguration, &propSize, NULL);
	if (err != noErr)
		return 0;
	
    if (propSize == 0)
        return 0;

	buflist = (AudioBufferList *)malloc(propSize);
	if (buflist == NULL)
		return 0;
	
    err = AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &propSize, buflist);
//	err = AudioDeviceGetProperty(deviceID, 0, isInput, kAudioDevicePropertyStreamConfiguration, &propSize, buflist);
	result = 0;
	if (err == noErr) {
		for (i = 0; i < buflist->mNumberBuffers; ++i) {
			result += buflist->mBuffers[i].mNumberChannels;
		}
	}
	
	free(buflist);
	return result;
}

static void
sMDAudioMusicDeviceInfoDestructor(void *p)
{
	MDAudioMusicDeviceInfo *info = (MDAudioMusicDeviceInfo *)p;
	if (info->name != NULL)
		free(info->name);
}

static MDStatus
sMDAudioUpdateHardwareDeviceInfo(void)
{
	UInt32 propsize;
	MDStatus err = noErr;
	int i, ndevs, isInput;
	AudioDeviceID *devs;
	MDArray *ary;
	
    AudioObjectPropertyAddress address;
    
    address.mSelector = kAudioHardwarePropertyDevices;
    address.mScope = kAudioObjectPropertyScopeGlobal;
    address.mElement = kAudioObjectPropertyElementMaster;
    
    err = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &propsize);
	if (err != noErr)
		return err;
	ndevs = propsize / sizeof(AudioDeviceID);
	devs = (AudioDeviceID *)malloc(sizeof(AudioDeviceID) * ndevs);
	if (devs == NULL)
		return kMDErrorOutOfMemory;

    err = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &propsize, devs);
	if (err != noErr)
		goto exit;
	if (gAudio->inputDeviceInfos == NULL) {
		gAudio->inputDeviceInfos = MDArrayNewWithDestructor(sizeof(MDAudioDeviceInfo), sMDAudioDeviceInfoDestructor);
		if (gAudio->inputDeviceInfos == NULL) {
			err = kMDErrorOutOfMemory;
			goto exit;
		}
	}
	if (gAudio->outputDeviceInfos == NULL) {
		gAudio->outputDeviceInfos = MDArrayNewWithDestructor(sizeof(MDAudioDeviceInfo), sMDAudioDeviceInfoDestructor);
		if (gAudio->outputDeviceInfos == NULL) {
			err = kMDErrorOutOfMemory;
			goto exit;
		}
	}
	for (isInput = 0; isInput < 2; isInput++) {
		MDAudioDeviceInfo info, *ip;
		ary = (isInput ? gAudio->inputDeviceInfos : gAudio->outputDeviceInfos);
		/*  Raise the internal flag for all registered deivces  */
		for (i = MDArrayCount(ary) - 1; i >= 0; i--) {
			ip = MDArrayFetchPtr(ary, i);
			ip->flags |= 1;
		}
		for (i = 0; i < ndevs; i++) {
			int nchan = sMDAudioDeviceCountChannels(devs[i], isInput);
			if (nchan == 0)
				continue;
			ip = MDAudioDeviceInfoForDeviceID(devs[i], isInput, NULL);
			if (ip != NULL) {
				/*  Already known  */
				ip->nChannels = nchan;
				ip->flags &= ~1;
				continue;
			} else {
				/*  Unknown device  */
				char buf[256];
				UInt32 maxlen = sizeof(buf) - 1;
				memset(&info, 0, sizeof(info));
				info.deviceID = devs[i];
				info.nChannels = sMDAudioDeviceCountChannels(devs[i], isInput);
                address.mSelector = kAudioDevicePropertyDeviceName;
                address.mScope = (isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput);
                err = AudioObjectGetPropertyData(devs[i], &address, 0, NULL, &maxlen, buf);
			//	err = AudioDeviceGetProperty(devs[i], 0, isInput, kAudioDevicePropertyDeviceName, &maxlen, buf);
				if (err != noErr)
					goto exit;
				buf[maxlen] = 0;
				info.name = strdup(buf);
				MyAppCallback_startupMessage("Initializing %s...", info.name);
				propsize = sizeof(UInt32);
                address.mSelector = kAudioDevicePropertySafetyOffset;
				if ((err = AudioObjectGetPropertyData(devs[i], &address, 0, NULL, &propsize, &info.safetyOffset)) != noErr)
					goto exit;
				propsize = sizeof(UInt32);
                address.mSelector = kAudioDevicePropertyBufferFrameSize;
				if ((err = AudioObjectGetPropertyData(devs[i], &address, 0, NULL, &propsize, &info.bufferSizeFrames)) != noErr)
					goto exit;
				propsize = sizeof(AudioStreamBasicDescription);
                address.mSelector = kAudioDevicePropertyStreamFormat;
				if ((err = AudioObjectGetPropertyData(devs[i], &address, 0, NULL, &propsize, &info.format)) != noErr)
					goto exit;
				if ((err = MDArrayInsert(ary, MDArrayCount(ary), 1, &info)) != kMDNoError)
					goto exit;
			}
		}
		/*  Remove non-present devices  */
		for (i = MDArrayCount(ary) - 1; i >= 0; i--) {
			ip = MDArrayFetchPtr(ary, i);
			if (ip->flags & 1)
				MDArrayDelete(ary, i, 1);
		}		
	}
	
exit:
	free(devs);
	return err;
}

static MDStatus
sMDAudioUpdateSoftwareDeviceInfo(int music_or_effect)
{
	AudioComponentDescription ccd, fcd;
	AudioComponent cmp = NULL;
	char *cName;
	int n, i;
    MDAudioMusicDeviceInfo info, *ip;
    MDArray **basep;
	OSStatus err;
	MDStatus status = kMDNoError;

    basep = (music_or_effect ? &(gAudio->musicDeviceInfos) : &(gAudio->effectDeviceInfos));
	if (*basep == NULL) {
		*basep = MDArrayNewWithDestructor(sizeof(MDAudioMusicDeviceInfo), sMDAudioMusicDeviceInfoDestructor);
		if (*basep == NULL) {
			return kMDErrorOutOfMemory;
		}
	}

	memset(&fcd, 0, sizeof(fcd));
    fcd.componentType = (music_or_effect ? kAudioUnitType_MusicDevice : kAudioUnitType_Effect);
	n = 0;
	while ((cmp = AudioComponentFindNext(cmp, &fcd)) != 0) {
        CFStringRef nameRef;
        CFIndex cflen;
    
		/*  Get the component information  */
        memset(&info, 0, sizeof(info));
        err = AudioComponentGetDescription(cmp, &ccd);
        if (err != noErr)
            continue;  /*  Cannot get valid description  */
        info.code = (((UInt64)ccd.componentSubType) << 32) + ((UInt64)ccd.componentManufacturer);

        /*  Get the component name  */
        err = AudioComponentCopyName(cmp, &nameRef);
        if (err != noErr)
            continue;  /*  Cannot get valid name  */
        cflen = CFStringGetLength(nameRef);
        if (cflen == 0)
            continue;  /*  Empty device name  */
        cName = malloc(cflen * 4 + 1);
        if (!CFStringGetCString(nameRef, cName, cflen * 4, kCFStringEncodingUTF8))
            continue;  /*  Cannot get valid name  */

        info.name = cName;

        for (i = 0; (ip = MDArrayFetchPtr(*basep, i)) != NULL; i++) {
			if (ip->code == info.code && strncmp(ip->name, cName, cflen) == 0) {
				free(info.name);
				info.name = NULL;
				break;
			}
		}
		if (ip != NULL)
			continue;  /*  This device is already known  */
		
        info.formatCached = 0;  /*  The information will be cached when first loaded  */
		
		if (err == noErr) {
			status = MDArrayInsert(*basep, MDArrayCount(*basep), 1, &info);
		} else {
			status = kMDErrorCannotSetupAudio;
		}
		if (status == kMDNoError)
			n++;
		else {
			free(info.name);
			info.name = NULL;
		}
	}
	MyAppCallback_startupMessage("");
	return status;
}

MDStatus
MDAudioUpdateDeviceInfo(void)
{
	MDStatus err;
	err = sMDAudioUpdateHardwareDeviceInfo();
	if (err == kMDNoError)
        err = sMDAudioUpdateSoftwareDeviceInfo(1);  /*  Music device  */
    if (err == kMDNoError)
        err = sMDAudioUpdateSoftwareDeviceInfo(0);  /*  Effects  */
    return err;
}

int
MDAudioDeviceCountInfo(int isInput)
{
	MDArray *ary = (isInput ? gAudio->inputDeviceInfos : gAudio->outputDeviceInfos);
	if (ary == NULL)
		return 0;
	return MDArrayCount(ary);
}

MDAudioDeviceInfo *
MDAudioDeviceInfoAtIndex(int idx, int isInput)
{
	MDArray *ary = (isInput ? gAudio->inputDeviceInfos : gAudio->outputDeviceInfos);
	if (ary == NULL)
		return NULL;
	return MDArrayFetchPtr(ary, idx);
}

MDAudioDeviceInfo *
MDAudioDeviceInfoForDeviceID(int deviceID, int isInput, int *deviceIndex)
{
	MDAudioDeviceInfo *ip;
	int i;
	MDArray *ary = (isInput ? gAudio->inputDeviceInfos : gAudio->outputDeviceInfos);
	if (ary == NULL)
		return NULL;
	for (i = 0; (ip = MDArrayFetchPtr(ary, i)) != NULL; i++) {
		if (ip->deviceID == deviceID) {
			if (deviceIndex != NULL)
				*deviceIndex = i;
			return ip;
		}
	}
	return NULL;
}					

MDAudioDeviceInfo *
MDAudioDeviceInfoWithName(const char *name, int isInput, int *deviceIndex)
{
	MDAudioDeviceInfo *ip;
	int i;
	MDArray *ary = (isInput ? gAudio->inputDeviceInfos : gAudio->outputDeviceInfos);
	if (ary == NULL)
		return NULL;
	for (i = 0; (ip = MDArrayFetchPtr(ary, i)) != NULL; i++) {
		if (strcmp(ip->name, name) == 0) {
			if (deviceIndex != NULL)
				*deviceIndex = i;
			return ip;
		}
	}
	return NULL;
}

int
MDAudioMusicDeviceCountInfo(void)
{
	if (gAudio->musicDeviceInfos != NULL)
		return MDArrayCount(gAudio->musicDeviceInfos);
	else return 0;
}

MDAudioMusicDeviceInfo *
MDAudioMusicDeviceInfoAtIndex(int idx)
{
	if (gAudio->musicDeviceInfos == NULL)
		return NULL;
	return MDArrayFetchPtr(gAudio->musicDeviceInfos, idx);
}

MDAudioMusicDeviceInfo *
MDAudioMusicDeviceInfoForCode(UInt64 code, int *outIndex)
{
	MDAudioMusicDeviceInfo *ip;
	int i;
	if (gAudio->musicDeviceInfos == NULL)
		return NULL;
	for (i = 0; (ip = MDArrayFetchPtr(gAudio->musicDeviceInfos, i)) != NULL; i++) {
		if (ip->code == code) {
			if (outIndex != NULL)
				*outIndex = i;
			return ip;
		}
	}
	if (outIndex != NULL)
		*outIndex = -1;
	return NULL;
}

int
MDAudioEffectDeviceCountInfo(void)
{
    if (gAudio->effectDeviceInfos != NULL)
        return MDArrayCount(gAudio->effectDeviceInfos);
    else return 0;
}

MDAudioMusicDeviceInfo *
MDAudioEffectDeviceInfoAtIndex(int idx)
{
    if (gAudio->effectDeviceInfos == NULL)
        return NULL;
    return MDArrayFetchPtr(gAudio->effectDeviceInfos, idx);
}

MDAudioMusicDeviceInfo *
MDAudioEffectDeviceInfoForCode(UInt64 code, int *outIndex)
{
    MDAudioMusicDeviceInfo *ip;
    int i;
    if (gAudio->effectDeviceInfos == NULL)
        return NULL;
    for (i = 0; (ip = MDArrayFetchPtr(gAudio->effectDeviceInfos, i)) != NULL; i++) {
        if (ip->code == code) {
            if (outIndex != NULL)
                *outIndex = i;
            return ip;
        }
    }
    if (outIndex != NULL)
        *outIndex = -1;
    return NULL;
}

MDAudioIOStreamInfo *
MDAudioGetIOStreamInfoAtIndex(int idx)
{
	if (idx < 0 || idx >= kMDAudioNumberOfStreams)
		return NULL;
	return &(gAudio->ioStreamInfos[idx]);
}

#if 0
#pragma mark ====== Managing Audio Graph ======
#endif

/*
   MDAudioIOStreamInfo *ip;
   MDAudioEffectChain *cp;
   MDAudioEffect *ep;

   ip->unit
    |
    +- cp->converterUnit
    |   |--> [ ep->effect 
    |   |       |--> {ep->converterUnit --->} ]n--+-->ip->effectMixerUnit
    |   |              (optional)                 |    (optional) |
    |   |--> [ ep->effect                         |               |
    |   |       |--> {ep->converterUnit --->} ]n--+               |
    |   ...            (optional)                                 |
    +- cp->converterUnit
    |   |--> [ ep->effect                                         |
    |   |       |--> {ep->converterUnit --->} ]n--+-->ip->effectMixerUnit
    |   |              (optional)                 |    (optional) |
    |   |--> [ ep->effect                         |               |
    |   |       |--> {ep->converterUnit --->} ]n--+               |
    |   ...            (optional)                                 |
    |                                                             v
                                                        gAudio->mixer
                                                                  v
                                                        gAudio->output
*/

/*  Disconnect the device output within the graph  */
static int
sMDAudioDisconnectDeviceOutput(int streamIndex)
{
    int i, result;
    AURenderCallbackStruct callback;
    MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(streamIndex);
    MDAudioEffectChain *cp;
    if (ip == NULL)
        return -1;
    if (ip->deviceIndex >= kMDAudioMusicDeviceIndexOffset) {
        /*  Music Device  */
        CHECK_ERR(result, AudioUnitRemoveRenderNotify(ip->unit, sMDAudioSendMIDIProc, ip));
        for (i = 0; i < ip->nchains; i++) {
            cp = ip->chains + i;
            if (cp->alive) {
                CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, cp->converterNode, 0));
            }
            CHECK_ERR(result, AudioUnitReset(cp->converterUnit, kAudioUnitScope_Global, 0));
        }
    } else {
        /*  Audio Device  */
        /*  Disable callback  */
        callback.inputProc = NULL;
        callback.inputProcRefCon = NULL;
        /*  Remove the callback from the converter unit (= entry to the effect chain) */
        for (i = 0; i < ip->nchains; i++) {
            cp = ip->chains + i;
            if (cp->alive) {
                CHECK_ERR(result, AudioUnitSetProperty(cp->converterUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(AURenderCallbackStruct)));
            }
            CHECK_ERR(result, AudioUnitReset(cp->converterUnit, kAudioUnitScope_Global, 0));
        }
    }
    CHECK_ERR(result, AudioUnitReset(gAudio->mixerUnit, kAudioUnitScope_Global, 0));
    return kMDNoError;
exit:
    return kMDErrorCannotSetupAudio;
}

MDStatus
MDAudioSelectIOStreamDevice(int idx, int deviceIndex)
{
    int i, n, len, shouldResumeGraph;
	OSStatus result = noErr;
	MDAudioIOStreamInfo *ip;
	MDAudioDeviceInfo *dp = NULL;
	MDAudioMusicDeviceInfo *mp = NULL;
    MDAudioEffectChain *cp;
    MDStatus sts;
    UInt32 propSize;
	AudioDeviceID audioDeviceID;
	AURenderCallbackStruct callback;
	unsigned char midiSetupChanged = 0;

	ip = MDAudioGetIOStreamInfoAtIndex(idx);
	if (ip == NULL)
		return kMDErrorCannotSetupAudio;
	
	/*  No change required?  */
	if (ip->deviceIndex == deviceIndex && ip->busIndex == idx)
		return kMDNoError;

    shouldResumeGraph = gAudio->isRunning;
    if (gAudio->isRunning) {
        CHECK_ERR(result, AUGraphStop(gAudio->graph));
        gAudio->isRunning = 0;
    }
	
	if (idx >= kMDAudioFirstIndexForOutputStream) {
		/*  Output stream  */
		dp = MDAudioDeviceInfoAtIndex(deviceIndex, 0);
		ip->deviceIndex = -1;  /*  Will be overwritten later  */
		if (dp == NULL) {
			/*  Leave the node as it is, just disabling the audio thru  */
			gAudio->isAudioThruEnabled = 0;
			ip->busIndex = -1;
		} else {
			if ((UInt64)(dp->deviceID) != ip->deviceID) {
				/*  Set the output device to the output unit  */
				audioDeviceID = dp->deviceID;
                result = AudioUnitSetProperty(gAudio->outputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &audioDeviceID, sizeof(AudioDeviceID));
				if (result == noErr) {
                    MDAudioFormat format;
                    /*  Initialize the audio unit  */
                    //CHECK_ERR(result, AudioUnitInitialize(gAudio->outputUnit));
                    /*  Set the preferred format of the output unit to the output side of the converter unit */
                    propSize = sizeof(MDAudioFormat);
                    CHECK_ERR(result, AudioUnitGetProperty(gAudio->outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Global, 0, &format, &propSize));
					gAudio->isAudioThruEnabled = 1;
                    ip->busIndex = idx;
					ip->deviceID = (UInt64)(dp->deviceID);
					ip->deviceIndex = deviceIndex;
                    /*  Reallocate buffer list  */
                    ip->bufferSizeFrames = dp->bufferSizeFrames;  /*  The buffer size of the underlying audio device; NOTE: dp must be alive until here!  */
                    if (ip->bufferList != NULL)
                        sMDAudioReleaseMyBufferList(ip->bufferList);
                    ip->bufferList = sMDAudioAllocateMyBufferList(gAudio->preferredFormat.mFormatFlags, gAudio->preferredFormat.mChannelsPerFrame, gAudio->preferredFormat.mBytesPerFrame, ip->bufferSizeFrames);
                    /*  Reallocate ring buffer  */
                    if (ip->ring != NULL)
                        MDRingBufferRelease(ip->ring);
                    ip->ring = MDRingBufferNew();
                    MDRingBufferAllocate(ip->ring, ip->bufferList->mNumberBuffers, gAudio->preferredFormat.mBytesPerFrame, dp->bufferSizeFrames * 4);
                    ip->firstInputTime = ip->firstOutputTime = -1;
				} else {
					gAudio->isAudioThruEnabled = 0;
					ip->busIndex = -1;
				}
			} else {
				gAudio->isAudioThruEnabled = 1;
                ip->busIndex = idx;
				ip->deviceIndex = deviceIndex;
			}
		}
	} else {
		/*  Input stream  */
		UInt64 newDeviceID;
		AudioComponentDescription desc;
        MDAudioFormat format = {0};
		if (deviceIndex >= kMDAudioMusicDeviceIndexOffset) {
			mp = MDAudioMusicDeviceInfoAtIndex(deviceIndex - kMDAudioMusicDeviceIndexOffset);
			newDeviceID = (mp != NULL ? mp->code : kMDAudioMusicDeviceUnknown);
            if (mp != NULL && mp->formatCached)
                format = mp->format;
		} else {
			dp = MDAudioDeviceInfoAtIndex(deviceIndex, 1);
			newDeviceID = (dp != NULL ? (UInt64)(dp->deviceID) : kMDAudioMusicDeviceUnknown);
            if (dp != NULL)
                format = dp->format;
		}

        if (ip->deviceID != kMDAudioMusicDeviceUnknown) {
            /*  Disable the current input  */
            CHECK_ERR(result, sMDAudioDisconnectDeviceOutput(idx));
            if (ip->deviceIndex >= kMDAudioMusicDeviceIndexOffset) {
                /*  Remove from the graph  */
                CHECK_ERR(result, AUGraphRemoveNode(gAudio->graph, ip->node));
                /*  Dispose MIDI controller name and MIDI buffers  */
                if (ip->midiControllerName != NULL) {
                    free(ip->midiControllerName);
                    ip->midiControllerName = NULL;
                }
                if (ip->midiBuffer != NULL) {
                    free(ip->midiBuffer);
                    ip->midiBuffer = NULL;
                }
                if (ip->bufferList != NULL) {
                    sMDAudioReleaseMyBufferList(ip->bufferList);
                    ip->bufferList = NULL;
                }
                if (ip->ring != NULL) {
                    MDRingBufferDeallocate(ip->ring);
                    ip->ring = NULL;
                }
                midiSetupChanged = 1;
            } else {
                /*  Dispose the input AudioUnit (AUHAL) */
                CHECK_ERR(result, AudioComponentInstanceDispose(ip->unit));
            }
            ip->deviceID = kMDAudioMusicDeviceUnknown;
            ip->node = 0;
            ip->unit = NULL;
            ip->deviceIndex = -1;
            ip->busIndex = -1;
		}

        if (newDeviceID != kMDAudioMusicDeviceUnknown) {
			/*  Enable the new input  */
            /*  Allocate the first converter unit if not present  */
            if (ip->nchains == 0) {
                ip->chains = (MDAudioEffectChain *)calloc(sizeof(MDAudioEffectChain), 8);
                ip->nchains = 1;
            }
            if (ip->chains->converterUnit == NULL) {
                /*  Create converter for the effector chain 0  */
                cp = ip->chains;
                desc.componentType = kAudioUnitType_FormatConverter;
                desc.componentSubType = kAudioUnitSubType_AUConverter;
                desc.componentManufacturer = kAudioUnitManufacturer_Apple;
                desc.componentFlags = desc.componentFlagsMask = 0;
                CHECK_ERR(result, AUGraphAddNode(gAudio->graph, &desc, &cp->converterNode));
                /*  Open component  */
                CHECK_ERR(result, AUGraphOpen(gAudio->graph));
                CHECK_ERR(result, AUGraphNodeInfo(gAudio->graph, cp->converterNode, NULL, &cp->converterUnit));
                /*  Set output format and connect to the mixer  */
                CHECK_ERR(result, AudioUnitSetProperty(cp->converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &gAudio->preferredFormat, sizeof(AudioStreamBasicDescription)));
                CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, cp->converterNode, 0, gAudio->mixer, idx));
            }
			if (deviceIndex >= kMDAudioMusicDeviceIndexOffset) {
                /*  Music Device  */
                /*  Create input node  */
                desc.componentType = kAudioUnitType_MusicDevice;
                desc.componentSubType = (UInt32)(newDeviceID >> 32);
                desc.componentManufacturer = (UInt32)(newDeviceID);
                desc.componentFlags = desc.componentFlagsMask = 0;
                CHECK_ERR(result, AUGraphAddNode(gAudio->graph, &desc, &ip->node));
                /*  Open component  */
                CHECK_ERR(result, AUGraphOpen(gAudio->graph));
                CHECK_ERR(result, AUGraphNodeInfo(gAudio->graph, ip->node, NULL, &ip->unit));
                /*  If this is the first load of this music device, then cache the internal information */
                if (!mp->formatCached) {
                    /*  Get the audio output format  */
                    propSize = sizeof(MDAudioFormat);
                    CHECK_ERR(result, AudioUnitGetProperty(ip->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &(mp->format), &propSize));
                    format = mp->format;
                    mp->acceptsCanonicalFormat = sMDAudioCompareFormat(&(mp->format), &gAudio->preferredFormat);
                    CHECK_ERR(result, AudioUnitGetPropertyInfo(ip->unit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &propSize, NULL));
                    if (propSize > 0)
                        mp->hasCustomView = kMDAudioHasCocoaView;
                    mp->formatCached = 1;
                }
                /*  Connect the output to the converter unit(s) and set format  */
                for (i = 0; i < ip->nchains; i++) {
                    cp = ip->chains + i;
                    result = AUGraphConnectNodeInput(gAudio->graph, ip->node, i, cp->converterNode, 0);
                    cp->alive = (result == noErr);
                    CHECK_ERR(result, AudioUnitSetProperty(cp->converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(AudioStreamBasicDescription)));
                }
                /*  Create the MIDI controller name  */
                len = (int)strlen(mp->name) + 5;
                ip->midiControllerName = (char *)malloc(len);
                strcpy(ip->midiControllerName, mp->name);
                /*  Check the duplicate  */
                for (i = 0, n = 2; i < kMDAudioNumberOfInputStreams; i++) {
                    MDAudioIOStreamInfo *ip2 = MDAudioGetIOStreamInfoAtIndex(i);
                    if (ip == ip2 || ip2->midiControllerName == NULL)
                        continue;
                    if (strcmp(ip->midiControllerName, ip2->midiControllerName) == 0) {
                        snprintf(ip->midiControllerName, len, "%s %d", mp->name, n);
                        n++;
                        i = -1;
                        continue;
                    }
                }
                /*  Allocate buffer for MIDI scheduling  */
                ip->midiBuffer = (unsigned char *)malloc(kMDAudioMIDIBufferSize);
                ip->midiBufferWriteOffset = 0;
                ip->midiBufferReadOffset = 0;
                /*  Set render notify callback  */
                CHECK_ERR(result, AudioUnitAddRenderNotify(ip->unit, sMDAudioSendMIDIProc, ip));
                midiSetupChanged = 1;
            } else {
                /*  Audio Device  */
                /*  Create HAL input unit (not connected to AUGraph)  */
                /*  Cf. Apple Technical Note 2091  */
                AudioComponent comp;
                UInt32 unum;
                MDAudioFormat deviceFormat, desiredFormat;
                desc.componentType = kAudioUnitType_Output;
                desc.componentSubType = kAudioUnitSubType_HALOutput;
                desc.componentManufacturer = kAudioUnitManufacturer_Apple;
                desc.componentFlags = 0;
                desc.componentFlagsMask = 0;
                comp = AudioComponentFindNext(NULL, &desc);
                if (comp == NULL)
                    return kMDErrorCannotSetupAudio;
                CHECK_ERR(result, AudioComponentInstanceNew(comp, &ip->unit));
                /*  Enable input  */
                unum = 1;
                CHECK_ERR(result, AudioUnitSetProperty(ip->unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &unum, sizeof(UInt32)));
                /*  Disable output  */
                unum = 0;
                CHECK_ERR(result, AudioUnitSetProperty(ip->unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &unum, sizeof(UInt32)));
                /*  Set the input device  */
                audioDeviceID = (AudioDeviceID)newDeviceID;
                CHECK_ERR(result, AudioUnitSetProperty(ip->unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &audioDeviceID, sizeof(AudioDeviceID)));
                /*  Obtain the device format  */
                unum = sizeof(MDAudioFormat);
                CHECK_ERR(result, AudioUnitGetProperty (ip->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &deviceFormat, &unum));
                desiredFormat = gAudio->preferredFormat;
                /*  Match the sample rate with the device */
                desiredFormat.mSampleRate = deviceFormat.mSampleRate;
                desiredFormat.mChannelsPerFrame = deviceFormat.mChannelsPerFrame;
                /*  If the device is mono, convert it to stereo by channel mapping  */
                if (deviceFormat.mChannelsPerFrame == 1) {
                    SInt32 *channelMap = (SInt32 *)malloc(2 * sizeof(SInt32));
                    channelMap[0] = 0;
                    channelMap[1] = 0;
                    unum = 2 * sizeof(SInt32);
                    CHECK_ERR(result, AudioUnitSetProperty(ip->unit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Output, 1, channelMap, unum));
                    free(channelMap);
                    desiredFormat.mChannelsPerFrame = 2;
                }
                /*   Set format to output scope  */
                CHECK_ERR(result, AudioUnitSetProperty(ip->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &desiredFormat, sizeof(AudioStreamBasicDescription)));
                /*  Reallocate buffer list  */
                ip->bufferSizeFrames = dp->bufferSizeFrames;  /*  The buffer size of the underlying audio device; NOTE: dp must be alive until here!  */
                ip->bufferList = sMDAudioAllocateMyBufferList(desiredFormat.mFormatFlags, desiredFormat.mChannelsPerFrame, desiredFormat.mBytesPerFrame, ip->bufferSizeFrames);
                /*  Set the AU callback function  */
                callback.inputProc = sMDAudioInputProc;
                callback.inputProcRefCon = ip;
                CHECK_ERR(result, AudioUnitSetProperty(ip->unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, sizeof(AURenderCallbackStruct)));
                /*  Connect the output to the converter unit(s) and set format  */
                callback.inputProc = sMDAudioPassProc;
                callback.inputProcRefCon = ip;
                for (i = 0; i < ip->nchains; i++) {
                    cp = ip->chains + i;
                    result = AudioUnitSetProperty(cp->converterUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, i, &callback, sizeof(AURenderCallbackStruct));
                    cp->alive = (result == noErr);
                    CHECK_ERR(result, AudioUnitSetProperty(cp->converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &desiredFormat, sizeof(AudioStreamBasicDescription)));
                }
                
                /*  Reallocate ring buffer  */
                ip->ring = MDRingBufferNew();
                MDRingBufferAllocate(ip->ring, ip->bufferList->mNumberBuffers, format.mBytesPerFrame, ip->bufferSizeFrames * 20);
                
                ip->firstInputTime = ip->firstOutputTime = -1;
                /*  Initialize and start the AUHAL  */
                CHECK_ERR(result, AudioUnitInitialize(ip->unit));
                CHECK_ERR(result, AudioOutputUnitStart(ip->unit));
            }
            ip->deviceIndex = deviceIndex;
            ip->busIndex = idx;
            ip->deviceID = newDeviceID;
            ip->format = format;
        }
	}
exit:
	sts = (result == noErr ? kMDNoError : kMDErrorCannotSetupAudio);
	if (sts == kMDNoError && midiSetupChanged)
		MDPlayerNotificationCallback();
    result = AudioUnitReset(gAudio->mixerUnit, kAudioUnitScope_Global, 0);
    if (shouldResumeGraph) {
        result = AUGraphStart(gAudio->graph);
        if (result == noErr)
            gAudio->isRunning = true;
    }
	return ((sts == kMDNoError && result == noErr) ? kMDNoError : kMDErrorCannotSetupAudio);
}

MDStatus
MDAudioGetIOStreamDevice(int idx, int *outDeviceIndex)
{
	if (idx < 0 || idx >= kMDAudioNumberOfStreams) {
		if (outDeviceIndex != NULL)
			*outDeviceIndex = -1;
		return kMDErrorCannotSetupAudio;
	}
	if (idx >= kMDAudioFirstIndexForOutputStream) {
		if (!gAudio->isAudioThruEnabled) {
			/*  Behave as if no device is set  */
			*outDeviceIndex = -1;
			return kMDNoError;
		}
	}
	if (outDeviceIndex != NULL)
		*outDeviceIndex = gAudio->ioStreamInfos[idx].deviceIndex;
	return kMDNoError;
}

#pragma mark ====== Audio Effects ======

MDStatus
MDAudioAppendEffectChain(int streamIndex)
{
    int sts, result, shouldResumeGraph;
    MDAudioIOStreamInfo *ip;
    MDAudioEffectChain *cp;
    MDAudioEffect *ep;
    AudioComponentDescription desc;
    AUNode node;
    
    if (streamIndex < 0 || streamIndex >= kMDAudioNumberOfInputStreams)
        return -1;  /*  Invalid streamIndex  */
    ip = MDAudioGetIOStreamInfoAtIndex(streamIndex);
    if (ip->nchains >= 64)
        return -2;  /*  Too many chains  */
    if (ip->nchains % 8 == 0) {
        /*  Allocate storage  */
        void *p = realloc(ip->chains, sizeof(MDAudioEffectChain) * (ip->nchains + 8));
        if (p == NULL)
            return -3;  /*  Out of memory  */
        ip->chains = p;
    }
    cp = ip->chains + ip->nchains;
    memset(cp, 0, sizeof(MDAudioEffectChain));
    ip->nchains++;
    
    shouldResumeGraph = gAudio->isRunning;
    if (gAudio->isRunning) {
        CHECK_ERR(result, AUGraphStop(gAudio->graph));
        gAudio->isRunning = 0;
    }
    
    /*  Create a converter (which is the entrance of the chain)  */
    desc.componentType = kAudioUnitType_FormatConverter;
    desc.componentSubType = kAudioUnitSubType_AUConverter;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = desc.componentFlagsMask = 0;
    CHECK_ERR(result, AUGraphAddNode(gAudio->graph, &desc, &cp->converterNode));
    /*  Open component  */
    CHECK_ERR(result, AUGraphOpen(gAudio->graph));
    CHECK_ERR(result, AUGraphNodeInfo(gAudio->graph, cp->converterNode, NULL, &cp->converterUnit));
    /*  Set output format  */
    CHECK_ERR(result, AudioUnitSetProperty(cp->converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &gAudio->preferredFormat, sizeof(AudioStreamBasicDescription)));
    /*  Create a mixer for this chain (when nchains == 2)  */
    if (ip->nchains == 2) {
        desc.componentType = kAudioUnitType_Mixer;
        desc.componentSubType = kAudioUnitSubType_StereoMixer;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;
        desc.componentFlags = desc.componentFlagsMask = 0;
        CHECK_ERR(result, AUGraphAddNode(gAudio->graph, &desc, &ip->effectMixerNode));
        CHECK_ERR(result, AUGraphOpen(gAudio->graph));
        CHECK_ERR(result, AUGraphNodeInfo(gAudio->graph, ip->effectMixerNode, NULL, &ip->effectMixerUnit));
        CHECK_ERR(result, AudioUnitSetProperty(ip->effectMixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Global, 0, &gAudio->preferredFormat, sizeof(AudioStreamBasicDescription)));
        /*  Disconnect the last unit in chain 0 from gAudio->mixer and
            reconnect to the ip->effectMixerNode  */
        CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, gAudio->mixer, streamIndex));
        if (ip->chains->neffects == 0)
            node = ip->chains->converterNode;
        else {
            /*  Last effect entry  */
            ep = ip->chains->effects + ip->chains->neffects - 1;
            if (ep->converterUnit != NULL)
                node = ep->converterNode;
            else node = ep->node;
        }
        CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, node, 0, ip->effectMixerNode, 0));
        /*  Connect ip->effectMixerNode to gAudio->mixer  */
        CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, ip->effectMixerNode, 0, gAudio->mixer, streamIndex));
    }
    /*  Connect cp->converterNode to ip->effectMixerNode  */
    CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, cp->converterNode, 0, ip->effectMixerNode, ip->nchains - 1));
    /*  Connect ip->unit to cp->converterNode  */
    if (ip->deviceIndex >= kMDAudioMusicDeviceIndexOffset) {
        /*  Music device  */
        UInt32 propSize, count;
        propSize = sizeof(UInt32);
        CHECK_ERR(result, AudioUnitGetProperty(ip->unit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Output, ip->node, &count, &propSize));
        if (count >= ip->nchains) {
            AudioStreamBasicDescription format;
            cp->alive = 1;
            CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, ip->node, ip->nchains - 1, cp->converterNode, 0));
            propSize = sizeof(AudioStreamBasicDescription);
            CHECK_ERR(result, AudioUnitGetProperty(ip->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, ip->nchains - 1, &format, &propSize));
            CHECK_ERR(result, AudioUnitSetProperty(cp->converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, propSize));
        } else cp->alive = 0;
    } else {
        /*  HAL: we do not support more than one stereo bus (for now)  */
        cp->alive = 0;
    }
    
exit:
    sts = (result == noErr ? kMDNoError : kMDErrorCannotSetupAudio);
    if (shouldResumeGraph) {
        result = AUGraphStart(gAudio->graph);
        if (result == noErr)
            gAudio->isRunning = 1;
    }
    return ((result == noErr && sts == kMDNoError) ? kMDNoError : kMDErrorCannotSetupAudio);
}

MDStatus
MDAudioRemoveLastEffectChain(int streamIndex)
{
    int sts, result, shouldResumeGraph;
    MDAudioIOStreamInfo *ip;
    MDAudioEffectChain *cp;
    MDAudioEffect *ep;
    AUNode node;
    
    if (streamIndex < 0 || streamIndex >= kMDAudioNumberOfInputStreams)
        return -1;  /*  Invalid streamIndex  */
    ip = MDAudioGetIOStreamInfoAtIndex(streamIndex);
    if (ip->nchains <= 1)
        return -2;  /*  At least one chain should be present  */
    cp = ip->chains + (ip->nchains - 1);
    if (cp->neffects > 0)
        return -3;  /*  The chain should be empty  */
    ip->nchains--;
    
    shouldResumeGraph = gAudio->isRunning;
    if (gAudio->isRunning) {
        CHECK_ERR(result, AUGraphStop(gAudio->graph));
        gAudio->isRunning = 0;
    }
    
    /*  Disonnect cp->converterNode from ip->effectMixerNode  */
    CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, ip->effectMixerNode, ip->nchains));
    /*  Disonnect ip->unit from cp->converterNode  */
    if (cp->alive != 0) {
        CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, cp->converterNode, 0));
    }
    /*  Dispose cp->converterNode  */
    CHECK_ERR(result, AUGraphRemoveNode(gAudio->graph, cp->converterNode));
    cp->converterNode = 0;
    cp->converterUnit = NULL;
    
    /*  Dispose the mixer for this chain (when nchains was 2)  */
    if (ip->nchains == 1) {
        /*  Disonnect ip->effectMixerNode from gAudio->mixer  */
        CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, gAudio->mixer, streamIndex));
        /*  Disconnect the last unit in chain 0 from ip->effectMixerNode and
            reconnect to gAudio->mixer   */
        CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, ip->effectMixerNode, 0));
        if (ip->chains->neffects == 0)
            node = ip->chains->converterNode;
        else {
            /*  Last effect entry  */
            ep = ip->chains->effects + ip->chains->neffects - 1;
            if (ep->converterUnit != NULL)
                node = ep->converterNode;
            else node = ep->node;
        }
        CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, node, 0, gAudio->mixer, streamIndex));
        /*  Dispose the mixer  */
        CHECK_ERR(result, AUGraphRemoveNode(gAudio->graph, ip->effectMixerNode));
        ip->effectMixerNode = 0;
        ip->effectMixerUnit = NULL;
    }

exit:
    sts = (result == noErr ? kMDNoError : kMDErrorCannotSetupAudio);
    if (shouldResumeGraph) {
        result = AUGraphStart(gAudio->graph);
        if (result == noErr)
            gAudio->isRunning = 1;
    }
    return ((result == noErr && sts == kMDNoError) ? kMDNoError : kMDErrorCannotSetupAudio);
}

MDStatus
MDAudioChangeEffect(int streamIndex, int chainIndex, int effectIndex, int effectID, int insert)
{
    int sts, result, shouldResumeGraph;
    MDAudioIOStreamInfo *ip;
    MDAudioEffectChain *cp;
    MDAudioEffect *ep;
    MDAudioMusicDeviceInfo *mp, *lastmp, *nextmp;
    AudioComponentDescription desc;
    AUNode lastNode, nextNode;
    int nextNodeBus;
    
    if (streamIndex < 0 || streamIndex >= kMDAudioNumberOfInputStreams)
        return -1;  /*  Invalid streamIndex  */
    ip = MDAudioGetIOStreamInfoAtIndex(streamIndex);
    if (chainIndex < 0 || chainIndex >= ip->nchains)
        return -2;  /*  Invalid chainIndex  */
    mp = MDAudioEffectDeviceInfoAtIndex(effectID);
    if (mp == NULL)
        return -3;  /*  effectID out of range  */
    cp = ip->chains + chainIndex;
    if (effectIndex < 0 || effectIndex > cp->neffects)
        return -4;  /*  Invalid effectIndex  */
    if (effectIndex == cp->neffects && insert == 0)
        return -4;  /*  Invalid effectIndex  */
    if (insert) {
        if (cp->neffects % 8 == 0) {
            /*  Allocate storage  */
            void *p = realloc(cp->effects, sizeof(MDAudioEffect) * (cp->neffects + 8));
            if (p == NULL)
                return -5;  /*  Out of memory  */
            cp->effects = p;
        }
        ep = cp->effects + effectIndex;
        if (effectIndex < cp->neffects) {
            memmove(ep + 1, ep, sizeof(MDAudioEffect) * (cp->neffects - effectIndex));
        }
        cp->neffects++;
        memset(ep, 0, sizeof(MDAudioEffect));
    } else {
        ep = cp->effects + effectIndex;
        if (ep->effectDeviceIndex == effectID)
            return 0;  /*  Same effect: no action  */
    }

    shouldResumeGraph = gAudio->isRunning;
    if (gAudio->isRunning) {
        CHECK_ERR(result, AUGraphStop(gAudio->graph));
        gAudio->isRunning = 0;
    }

    /*  Specify next nodes and disable the existing connection to it  */
    if (effectIndex == cp->neffects - 1) {
        if (ip->effectMixerUnit != NULL) {
            nextNode = ip->effectMixerNode;
            nextNodeBus = chainIndex;
        } else {
            nextNode = gAudio->mixer;
            nextNodeBus = streamIndex;
        }
    } else {
        nextNode = ep[1].node;
        nextNodeBus = 0;
    }
    CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, nextNode, nextNodeBus));

    if (!insert) {
        /*  Disable the connection to the converter, if present  */
        if (ep->converterUnit != NULL) {
            CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, ep->converterNode, 0));
            /*  Note: the converter unit will be disposed later, if it is unnecessary */
        }
        /*  Disable the existing connection to the present node  */
        CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, ep->node, 0));
        /*  Dispose the present node  */
        CHECK_ERR(result, AUGraphRemoveNode(gAudio->graph, ep->node));
        ep->node = 0;
        ep->unit = NULL;
    }

    /*  Create a new effect node  */
    desc.componentType = kAudioUnitType_Effect;
    desc.componentSubType = (UInt32)(mp->code >> 32);
    desc.componentManufacturer = (UInt32)(mp->code);
    desc.componentFlags = desc.componentFlagsMask = 0;
    CHECK_ERR(result, AUGraphAddNode(gAudio->graph, &desc, &ep->node));
    CHECK_ERR(result, AUGraphOpen(gAudio->graph));
    CHECK_ERR(result, AUGraphNodeInfo(gAudio->graph, ep->node, NULL, &ep->unit));
    /*  If this is the first load of this effect device, then cache the internal information */
    if (!mp->formatCached) {
        UInt32 propSize;
        /*  Get the audio output format  */
        propSize = sizeof(MDAudioFormat);
        CHECK_ERR(result, AudioUnitGetProperty(ep->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &(mp->format), &propSize));
        mp->acceptsCanonicalFormat = sMDAudioCompareFormat(&(mp->format), &gAudio->preferredFormat);
        result = AudioUnitGetPropertyInfo(ep->unit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &propSize, NULL);
        if (result == 0 && propSize > 0)
            mp->hasCustomView = kMDAudioHasCocoaView;
        mp->formatCached = 1;
    }

    if (effectIndex == 0) {
        lastNode = cp->converterNode;
        lastmp = NULL;
        /*  Set output format of the converter unit  */
        CHECK_ERR(result, AudioUnitSetProperty(cp->converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &mp->format, sizeof(AudioStreamBasicDescription)));
    } else {
        lastmp = MDAudioEffectDeviceInfoAtIndex(ep[-1].effectDeviceIndex);
        if (sMDAudioCompareFormat(&mp->format, &lastmp->format)) {
            /*  We do not need converter in the last effect block  */
            if (ep[-1].converterUnit != NULL) {
                CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, ep[-1].converterNode, 0));
                CHECK_ERR(result, AUGraphRemoveNode(gAudio->graph, ep[-1].converterNode));
                ep[-1].converterNode = 0;
                ep[-1].converterUnit = NULL;
            }
            lastNode = ep[-1].node;
        } else {
            /*  We do need converter  */
            if (ep[-1].converterUnit == NULL) {
                /*  Create ep->converterNode  */
                desc.componentType = kAudioUnitType_FormatConverter;
                desc.componentSubType = kAudioUnitSubType_AUConverter;
                desc.componentManufacturer = kAudioUnitManufacturer_Apple;
                desc.componentFlags = desc.componentFlagsMask = 0;
                CHECK_ERR(result, AUGraphAddNode(gAudio->graph, &desc, &ep[-1].converterNode));
                /*  Open component  */
                CHECK_ERR(result, AUGraphOpen(gAudio->graph));
                CHECK_ERR(result, AUGraphNodeInfo(gAudio->graph, ep[-1].converterNode, NULL, &ep[-1].converterUnit));
                /*  Set input format  */
                CHECK_ERR(result, AudioUnitSetProperty(ep[-1].converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &lastmp->format, sizeof(AudioStreamBasicDescription)));
                /*  Reconnect effect->converter->next  */
                CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, ep[-1].node, 0, ep[-1].converterNode, 0));
            }
            lastNode = ep[-1].converterNode;
            /*  Set output format of the converter unit  */
            CHECK_ERR(result, AudioUnitSetProperty(ep[-1].converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &mp->format, sizeof(AudioStreamBasicDescription)));
        }
    }
    /*  Connect last node  */
    CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, lastNode, 0, ep->node, 0));
    /*  Do we need a converter after the effect?  */
    if (effectIndex >= cp->neffects - 1) {
        nextmp = NULL;
        result = mp->acceptsCanonicalFormat;
    } else {
        nextmp = MDAudioEffectDeviceInfoAtIndex(ep[1].effectDeviceIndex);
        result = sMDAudioCompareFormat(&mp->format, &nextmp->format);
    }
    if (result == 0) {
        /*  We do need a converter  */
        if (ep->converterUnit == NULL) {
            desc.componentType = kAudioUnitType_FormatConverter;
            desc.componentSubType = kAudioUnitSubType_AUConverter;
            desc.componentManufacturer = kAudioUnitManufacturer_Apple;
            desc.componentFlags = desc.componentFlagsMask = 0;
            CHECK_ERR(result, AUGraphAddNode(gAudio->graph, &desc, &ep->converterNode));
            /*  Open component  */
            CHECK_ERR(result, AUGraphOpen(gAudio->graph));
            CHECK_ERR(result, AUGraphNodeInfo(gAudio->graph, ep->converterNode, NULL, &ep->converterUnit));
        }
        /*  Set output format  */
        CHECK_ERR(result, AudioUnitSetProperty(ep->converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, (nextmp == NULL ? &gAudio->preferredFormat : &nextmp->format), sizeof(AudioStreamBasicDescription)));
        /*  Set input format  */
        CHECK_ERR(result, AudioUnitSetProperty(ep->converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &mp->format, sizeof(AudioStreamBasicDescription)));
        /*  Connect effect to converter  */
        CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, ep->node, 0, ep->converterNode, 0));
        /*  Connect converter to the next node  */
        CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, ep->converterNode, 0, nextNode, nextNodeBus));
    } else {
        /*  Connect effect to the next node  */
        CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, ep->node, 0, nextNode, nextNodeBus));
        /*  Dispose the existing converter, as we do not need it  */
        if (ep->converterUnit != NULL) {
            CHECK_ERR(result, AUGraphRemoveNode(gAudio->graph, ep->converterNode));
            ep->converterNode = 0;
            ep->converterUnit = NULL;
        }
    }
    ep->effectDeviceIndex = effectID;
    ep->name = strdup(mp->name);

exit:
    sts = (result == noErr ? kMDNoError : kMDErrorCannotSetupAudio);
    if (shouldResumeGraph) {
        result = AUGraphStart(gAudio->graph);
        if (result == noErr)
            gAudio->isRunning = 1;
    }
    return ((result == noErr && sts == kMDNoError) ? kMDNoError : kMDErrorCannotSetupAudio);
}

MDStatus
MDAudioRemoveEffect(int streamIndex, int chainIndex, int effectIndex)
{
    int sts, result, shouldResumeGraph;
    MDAudioIOStreamInfo *ip;
    MDAudioEffectChain *cp;
    MDAudioEffect *ep;
    MDAudioMusicDeviceInfo *mp, *lastmp;
    AudioStreamBasicDescription *fmtp;
    AudioComponentDescription desc;
    AUNode lastNode, nextNode;
    int nextNodeBus;
    
    if (streamIndex < 0 || streamIndex >= kMDAudioNumberOfInputStreams)
        return -1;  /*  Invalid streamIndex  */
    ip = MDAudioGetIOStreamInfoAtIndex(streamIndex);
    if (chainIndex < 0 || chainIndex >= ip->nchains)
        return -2;  /*  Invalid chainIndex  */
    cp = ip->chains + chainIndex;
    if (effectIndex < 0 || effectIndex >= cp->neffects)
        return -4;  /*  Invalid effectIndex  */
    ep = cp->effects + effectIndex;
    
    shouldResumeGraph = gAudio->isRunning;
    if (gAudio->isRunning) {
        CHECK_ERR(result, AUGraphStop(gAudio->graph));
        gAudio->isRunning = 0;
    }
    
    /*  Specify next nodes and disable the existing connection to it  */
    if (effectIndex == cp->neffects - 1) {
        mp = NULL;
        if (ip->effectMixerUnit != NULL) {
            nextNode = ip->effectMixerNode;
            nextNodeBus = chainIndex;
        } else {
            nextNode = gAudio->mixer;
            nextNodeBus = streamIndex;
        }
        fmtp = &gAudio->preferredFormat;
    } else {
        nextNode = ep[1].node;
        nextNodeBus = 0;
        mp = MDAudioEffectDeviceInfoAtIndex(ep[1].effectDeviceIndex);
        fmtp = &mp->format;
    }
    CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, nextNode, nextNodeBus));
    
    /*  Disable the connection to the converter, if present  */
    if (ep->converterUnit != NULL) {
        CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, ep->converterNode, 0));
        CHECK_ERR(result, AUGraphRemoveNode(gAudio->graph, ep->converterNode));
    }

    /*  Disable the existing connection to the present node  */
    CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, ep->node, 0));
    /*  Dispose the present node  */
    CHECK_ERR(result, AUGraphRemoveNode(gAudio->graph, ep->node));
    
    /*  Specify the last node  */
    if (effectIndex == 0) {
        lastNode = cp->converterNode;
        lastmp = NULL;
        /*  Set output format of the converter unit  */
        CHECK_ERR(result, AudioUnitSetProperty(cp->converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, fmtp, sizeof(AudioStreamBasicDescription)));
    } else {
        lastmp = MDAudioEffectDeviceInfoAtIndex(ep[-1].effectDeviceIndex);
        if (sMDAudioCompareFormat(fmtp, &lastmp->format)) {
            /*  We do not need converter in the last effect block  */
            if (ep[-1].converterUnit != NULL) {
                CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, ep[-1].converterNode, 0));
                CHECK_ERR(result, AUGraphRemoveNode(gAudio->graph, ep[-1].converterNode));
                ep[-1].converterNode = 0;
                ep[-1].converterUnit = NULL;
            }
            lastNode = ep[-1].node;
        } else {
            /*  We do need converter  */
            if (ep[-1].converterUnit == NULL) {
                /*  Create ep->converterNode  */
                desc.componentType = kAudioUnitType_FormatConverter;
                desc.componentSubType = kAudioUnitSubType_AUConverter;
                desc.componentManufacturer = kAudioUnitManufacturer_Apple;
                desc.componentFlags = desc.componentFlagsMask = 0;
                CHECK_ERR(result, AUGraphAddNode(gAudio->graph, &desc, &ep[-1].converterNode));
                /*  Open component  */
                CHECK_ERR(result, AUGraphOpen(gAudio->graph));
                CHECK_ERR(result, AUGraphNodeInfo(gAudio->graph, ep[-1].converterNode, NULL, &ep[-1].converterUnit));
                /*  Set input format  */
                CHECK_ERR(result, AudioUnitSetProperty(ep[-1].converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &lastmp->format, sizeof(AudioStreamBasicDescription)));
                /*  Reconnect effect->converter->next  */
                CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, ep[-1].node, 0, ep[-1].converterNode, 0));
            }
            lastNode = ep[-1].converterNode;
            /*  Set output format of the converter unit  */
            CHECK_ERR(result, AudioUnitSetProperty(ep[-1].converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, fmtp, sizeof(AudioStreamBasicDescription)));
        }
    }
    /*  Connect last node  */
    CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, lastNode, 0, nextNode, nextNodeBus));
    
exit:
    if (effectIndex < cp->neffects - 1) {
        memmove(ep, ep + 1, sizeof(MDAudioEffect) * (cp->neffects - effectIndex - 1));
    }
    cp->neffects--;
    sts = (result == noErr ? kMDNoError : kMDErrorCannotSetupAudio);
    if (shouldResumeGraph) {
        result = AUGraphStart(gAudio->graph);
        if (result == noErr)
            gAudio->isRunning = 1;
    }
    return ((result == noErr && sts == kMDNoError) ? kMDNoError : kMDErrorCannotSetupAudio);
}

#if 0
#pragma mark ====== Initialize Audio ======
#endif

MDStatus
MDAudioInitialize(void)
{
    AudioComponentDescription desc;
    AURenderCallbackStruct	callback;
    OSStatus err;
    UInt32 unum;
    int i;
    
    if (gAudio != NULL)
        return kMDNoError;
    gAudio = (MDAudio *)malloc(sizeof(MDAudio));
    if (gAudio == NULL)
        return kMDErrorOutOfMemory;
    memset(gAudio, 0, sizeof(MDAudio));
    
    /*  The preferred audio format  */
    MDAudioFormatSetCanonical(&gAudio->preferredFormat, 44100.0f, 2, 0);
    
    /*  Initialize IOStreamInfo  */
    for (i = 0; i < kMDAudioNumberOfStreams; i++) {
        MDAudioIOStreamInfo *ip = &(gAudio->ioStreamInfos[i]);
        ip->deviceIndex = -1;
        ip->busIndex = -1;
        ip->pan = 0.5;
        ip->volume = 1.0;
    }
    
    /*  Load audio device info  */
    MDAudioUpdateDeviceInfo();
    
    MyAppCallback_startupMessage("Creating AudioUnit Graph...");
    
    /*  Create AUGraph  */
    CHECK_ERR(err, NewAUGraph(&gAudio->graph));
    
    /*  Mixer  */
    desc.componentType = kAudioUnitType_Mixer;
    desc.componentSubType = kAudioUnitSubType_StereoMixer;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = desc.componentFlagsMask = 0;
    CHECK_ERR(err, AUGraphAddNode(gAudio->graph, &desc, &gAudio->mixer));
    
    /*  Output  */
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_DefaultOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    CHECK_ERR(err, AUGraphAddNode(gAudio->graph, &desc, &gAudio->output));
    
    /*  Open graph and load components  */
    CHECK_ERR(err, AUGraphOpen(gAudio->graph));
    CHECK_ERR(err, AUGraphNodeInfo(gAudio->graph, gAudio->mixer, &desc, &gAudio->mixerUnit));
    CHECK_ERR(err, AUGraphNodeInfo(gAudio->graph, gAudio->output, &desc, &gAudio->outputUnit));
    
    /*  Set the canonical format to the mixer unit  */
    CHECK_ERR(err, AudioUnitSetProperty(gAudio->mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Global, 0, &gAudio->preferredFormat, sizeof(AudioStreamBasicDescription)));

    /*  Set the AU callback function for the output unit  */
    /*  (Read output from the converter and pass to the output _and_ record to the file)  */
    callback.inputProc = sMDAudioRecordProc;
    callback.inputProcRefCon = &(gAudio->ioStreamInfos[kMDAudioFirstIndexForOutputStream]);
    CHECK_ERR(err, AudioUnitSetProperty(gAudio->outputUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(AURenderCallbackStruct)));
    
    /*  Enable metering for the stereo mixer  */
    unum = 1;
    CHECK_ERR(err, AudioUnitSetProperty(gAudio->mixerUnit, kAudioUnitProperty_MeteringMode, kAudioUnitScope_Global, 0, &unum, sizeof(UInt32)));
    
    CHECK_ERR(err, AUGraphInitialize(gAudio->graph));
    CHECK_ERR(err, AUGraphStart(gAudio->graph));
    gAudio->isRunning = 1;
    
    {
        int deviceIndex;
        MDStatus sts;
        UInt64 code;
        /*  Open 2 instances of DLS synthesizer  */
        MyAppCallback_startupMessage("Initializing Internal Synthesizer...");
        code = ((UInt64)kAudioUnitSubType_DLSSynth << 32) + (UInt64)kAudioUnitManufacturer_Apple;
        MDAudioMusicDeviceInfoForCode(code, &deviceIndex);
        if (deviceIndex >= 0) {
            sts = MDAudioSelectIOStreamDevice(0, deviceIndex + kMDAudioMusicDeviceIndexOffset);
            if (sts == 0)
                sts = MDAudioSelectIOStreamDevice(1, deviceIndex + kMDAudioMusicDeviceIndexOffset);
            if (sts != 0)
                return sts;
        }
    }
    
    /*  Set built-in output as the audio output  */
    CHECK_ERR(err, MDAudioSelectIOStreamDevice(kMDAudioFirstIndexForOutputStream, 0));
    
    return 0;
    
exit:
    return kMDErrorCannotSetupAudio;
}

MDStatus
MDAudioDispose(void)
{
    int idx;
    OSStatus err;
    for (idx = 0; idx < kMDAudioNumberOfStreams; idx++)
        MDAudioSelectIOStreamDevice(idx, -1);
    if (gAudio->isRunning) {
        CHECK_ERR(err, AUGraphStop(gAudio->graph));
        gAudio->isRunning = 0;
    }
    CHECK_ERR(err, AUGraphClose(gAudio->graph));
    gAudio->graph = NULL;
    return kMDNoError;
exit:
    return kMDErrorCannotSetupAudio;
}

#pragma mark ====== Start/Stop Audio input/output ======

MDStatus
MDAudioGetMixerBusAttributes(int idx, float *outPan, float *outVolume, float *outAmpLeft, float *outAmpRight, float *outPeakLeft, float *outPeakRight)
{
	OSStatus err;
	Float32 f32;
    int scope, mixerIndex;
	if (idx >= 0 && idx < kMDAudioNumberOfInputStreams) {
        mixerIndex = idx;
		scope = kAudioUnitScope_Input;
	} else if (idx >= kMDAudioFirstIndexForOutputStream && idx < kMDAudioNumberOfStreams) {
		mixerIndex = idx - kMDAudioFirstIndexForOutputStream;
		scope = kAudioUnitScope_Output;
	} else return kMDErrorCannotSetupAudio;
	if (scope == kAudioUnitScope_Input) {
		CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_Pan, scope, mixerIndex, &f32));
	} else f32 = 0.5f;
    gAudio->ioStreamInfos[idx].pan = f32;
	if (outPan != NULL)
		*outPan = f32;	
	CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_Volume, scope, mixerIndex, &f32));
    gAudio->ioStreamInfos[idx].volume = f32;
	if (outVolume != NULL)
		*outVolume = f32;
	CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_PostAveragePower, scope, mixerIndex, &f32));
	if (outAmpLeft != NULL)
		*outAmpLeft = f32;
	CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_PostAveragePower + 1, scope, mixerIndex, &f32));
	if (outAmpRight != NULL)
		*outAmpRight = f32;
	CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_PostPeakHoldLevel, scope, mixerIndex, &f32));
	if (outPeakLeft != NULL)
		*outPeakLeft = f32;
	CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_PostPeakHoldLevel + 1, scope, mixerIndex, &f32));
	if (outPeakRight != NULL)
		*outPeakRight = f32;
	return kMDNoError;
exit:
	return kMDErrorCannotSetupAudio;
}

MDStatus
MDAudioSetMixerVolume(int idx, float volume)
{
	OSStatus err;
	Float32 f32 = volume;
    int scope, mixerIndex;
	if (idx >= 0 && idx < kMDAudioNumberOfInputStreams) {
        mixerIndex = idx;
		scope = kAudioUnitScope_Input;
	} else if (idx >= kMDAudioFirstIndexForOutputStream && idx < kMDAudioNumberOfStreams) {
		mixerIndex = idx - kMDAudioFirstIndexForOutputStream;
		scope = kAudioUnitScope_Output;
	} else return kMDErrorCannotSetupAudio;
	CHECK_ERR(err, AudioUnitSetParameter(gAudio->mixerUnit, kStereoMixerParam_Volume, scope, mixerIndex, f32, 0));
    gAudio->ioStreamInfos[idx].volume = volume;
	return kMDNoError;
exit:
	return kMDErrorCannotSetupAudio;
}

MDStatus
MDAudioSetMixerPan(int idx, float pan)
{
	OSStatus err;
	Float32 f32 = pan;
	int scope, mixerIndex;
	if (idx >= 0 && idx < kMDAudioNumberOfInputStreams) {
        mixerIndex = idx;
		scope = kAudioUnitScope_Input;
	} else if (idx >= kMDAudioFirstIndexForOutputStream && idx < kMDAudioNumberOfStreams) {
		mixerIndex = idx - kMDAudioFirstIndexForOutputStream;
		scope = kAudioUnitScope_Output;
	} else return kMDErrorCannotSetupAudio;
	CHECK_ERR(err, AudioUnitSetParameter(gAudio->mixerUnit, kStereoMixerParam_Pan, scope, mixerIndex, f32, 0));
    gAudio->ioStreamInfos[idx].pan = pan;
	return kMDNoError;
exit:
	return kMDErrorCannotSetupAudio;
}

#if 0
MDStatus
MDAudioStartInput(void)
{
	OSStatus err;
	if (!gAudio->isInputRunning) {
	//	return kMDErrorCannotSetupAudio;
		CHECK_ERR(err, AudioOutputUnitStart(gAudio->inputUnit));
		gAudio->isInputRunning = 1;
		gAudio->firstInputTime = -1;
	}
	
	return kMDNoError;
exit:
	return kMDErrorCannotSetupAudio;
}

MDStatus
MDAudioStopInput(void)
{
	OSStatus err;
	if (!gAudio->isInputRunning) {
	//	return kMDErrorCannotSetupAudio;
		CHECK_ERR(err, AudioOutputUnitStop(gAudio->inputUnit));
		gAudio->isInputRunning = 0;
		gAudio->firstInputTime = -1;
	}
	return kMDNoError;
exit:
	return kMDErrorCannotSetupAudio;
}

MDStatus
MDAudioEnablePlayThru(int flag)
{
	MDStatus sts;
	if (flag && !gAudio->isAudioThruEnabled) {
	/*	if (!gAudio->isInputRunning) {
			if ((sts = MDAudioStartInput()) != kMDNoError)
				return sts;
		} */
		gAudio->isAudioThruEnabled = 1;
	} else if (!flag && gAudio->isAudioThruEnabled) {
	/*	if (!gAudio->isRecording) {
			if ((sts = MDAudioStopInput()) != kMDNoError)
				return sts;
		} */
		gAudio->isAudioThruEnabled = 0;
	}
	return kMDNoError;
}

int
MDAudioIsPlayThruEnabled(void)
{
	return gAudio->isAudioThruEnabled;
}

int
MDAudioGetInputVolumeAndAmplitudes(float *outVolume, float *outAmpLeft, float *outAmpRight, float *outPeakLeft, float *outPeakRight)
{
	OSStatus err;
	Float32 f32;
	if (gAudio != NULL && gAudio->mixerUnit != NULL) {
		CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_Volume, kAudioUnitScope_Input, 2, &f32));
		if (outVolume != NULL)
			*outVolume = f32;
		CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_PostAveragePower, kAudioUnitScope_Input, 2, &f32));
		if (outAmpLeft != NULL)
			*outAmpLeft = f32;
		CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_PostAveragePower + 1, kAudioUnitScope_Input, 2, &f32));
		if (outAmpRight != NULL)
			*outAmpRight = f32;
		CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_PostPeakHoldLevel, kAudioUnitScope_Input, 2, &f32));
		if (outPeakLeft != NULL)
			*outPeakLeft = f32;
		CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_PostPeakHoldLevel + 1, kAudioUnitScope_Input, 2, &f32));
		if (outPeakRight != NULL)
			*outPeakRight = f32;
	}
	return kMDNoError;
exit:
	return kMDErrorCannotSetupAudio;
}

int
MDAudioSetInputVolume(float volume)
{
	OSStatus err;
	Float32 f32 = volume;
	if (gAudio != NULL && gAudio->mixerUnit != NULL) {
		CHECK_ERR(err, AudioUnitSetParameter(gAudio->mixerUnit, kStereoMixerParam_Volume, kAudioUnitScope_Input, 2, f32, 0));
	}
	return kMDNoError;
exit:
	return kMDErrorCannotSetupAudio;
}
#endif

#pragma mark ====== Audio Recording ======

/*  Prepare for Audio recording. 0 <= bus <= kMDAudioNumberOfInputStreams: input AUHAL, 0xffff: capture standard audio output  */
MDStatus
MDAudioPrepareRecording(int bus, const char *filename, const MDAudioFormat *format, int audioFileType, UInt64 recordingDuration, int thruEnabled)
{
	OSStatus err;
    CFURLRef urlRef;
    ExtAudioFileRef audioFile;
	
	if (gAudio->isRecording)
		return kMDErrorCannotSetupAudio;
	
    /*  Prepare CFURLRef from the filename (assuming it is a full path)  */
    urlRef = CFURLCreateFromFileSystemRepresentation(NULL, (const unsigned char *)filename, strlen(filename), 0);
    
	/*  Create a new audio file  */
    err = ExtAudioFileCreateWithURL(urlRef, audioFileType, format, NULL, kAudioFileFlags_EraseFile, &audioFile);
	if (err != noErr)
		return kMDErrorCannotSetupAudio;
    CFRelease(urlRef);

	/*  Set the client data format  */
    err = ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &gAudio->preferredFormat);
    if (err != noErr)
        return kMDErrorCannotSetupAudio;
    
    /*  Initialize AudioFile IO  */
    err = ExtAudioFileWriteAsync(audioFile, 0, NULL);
    if (err != noErr)
        return kMDErrorCannotSetupAudio;

    if (bus >= 0 && bus < kMDAudioNumberOfInputStreams) {
        MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(bus);
        ip->audioFile = audioFile;
        ip->recordingDuration = recordingDuration;
        ip->recordingStartTime = 0;
        ip->thruEnabled = thruEnabled;
    } else {
        gAudio->audioFile = audioFile;
        gAudio->recordingDuration = recordingDuration;
        gAudio->recordingStartTime = 0;
        gAudio->thruEnabled = thruEnabled;
    }

	return kMDNoError;
}

MDStatus
MDAudioStartRecording(void)
{
	if (gAudio->isRecording)
		return kMDErrorCannotSetupAudio;
	gAudio->isRecording = 1;
	return kMDNoError;
}

MDStatus
MDAudioStopRecording(void)
{
	OSStatus err;
    int bus;
	if (!gAudio->isRecording)
		return kMDErrorCannotProcessAudio;
	gAudio->isRecording = 0;
    for (bus = -1; bus < kMDAudioNumberOfInputStreams; bus++) {
        ExtAudioFileRef *aref;
        if (bus == -1)
            aref = &(gAudio->audioFile);
        else
            aref = &(MDAudioGetIOStreamInfoAtIndex(bus)->audioFile);
        if (*aref != NULL) {
            err = ExtAudioFileDispose(*aref);
            *aref = NULL;
            if (err != 0)
                return kMDErrorCannotProcessAudio;
        }
    }
	return kMDNoError;
}

/*
MDStatus
MDAudioStop(void)
{
	MDStatus status = kMDNoError;
	if (inAudio != NULL) {
		if (inAudio->isRecording)
			status = MDAudioStopRecording(inAudio);
	}
	return status;
}
*/

int
MDAudioIsRecording(void)
{
	if (gAudio->isRecording)
		return 1;
	else return 0;
}

#pragma mark ====== MDAudioFormat accessors ======

void
MDAudioFormatSetCanonical(MDAudioFormat *fmt, float sampleRate, int nChannels, int interleaved)
{
	if (sampleRate != 0.0)
		fmt->mSampleRate = sampleRate;
	fmt->mFormatID = kAudioFormatLinearPCM;
	fmt->mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
	fmt->mBitsPerChannel = 32;
	fmt->mChannelsPerFrame = nChannels;
	fmt->mFramesPerPacket = 1;
	if (interleaved)
		fmt->mBytesPerPacket = fmt->mBytesPerFrame = nChannels * sizeof(Float32);
	else {
		fmt->mBytesPerPacket = fmt->mBytesPerFrame = sizeof(Float32);
		fmt->mFormatFlags |= kAudioFormatFlagIsNonInterleaved;
	}
}

/*  Not used yet 
MDAudioFormatSetSampleRate(MDAudioFormat *fmt, float sampleRate)
{	fmt->mSampleRate = sampleRate;  }

float
MDAudioFormatGetSampleRate(MDAudioFormat *fmt)
{	return fmt->mSampleRate;  }

void
MDAudioFormatSetFormatID(MDAudioFormat *fmt, UInt32 formatID)
{	fmt->mFormatID = formatID;  }

UInt32
MDAudioFormatGetFormatID(MDAudioFormat *fmt)
{	return fmt->formatID;  }
*/

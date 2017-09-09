/*
 *  MDAudio_MacOSX.c
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 08/01/06.
 *  Copyright 2008-2016 Toshi Nagata. All rights reserved.
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
#include <CoreServices/CoreServices.h>
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
/*	int isInputRunning;
	int isRunning; */
	
	/*  Audio Units  */
	AudioUnit mixerUnit, outputUnit;
/*	AudioUnit inputUnit, outputUnit, mixerUnit, converterUnit;
	MusicDeviceComponent musicDevice, musicDevice2;
	AUMIDIControllerRef midiCon, midiCon2; */
	
	/*  Audio/Music device infos  */
	MDArray *inputDeviceInfos, *outputDeviceInfos;
	MDArray *musicDeviceInfos;
	
	/*  IO information (the mixer input/output)  */
	MDAudioIOStreamInfo ioStreamInfos[kMDAudioNumberOfStreams];
	int isAudioThruEnabled;

	/*  Feeding audio from external device  */
/*	AudioBufferList *inputBufferList; */

	/*  Recording to file  */
	ExtAudioFileRef audioFile;
	int isRecording;
	
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
sMDAudioAllocateMyBufferList(UInt32 channelsPerFrame, UInt32 bytesPerFrame, UInt32 numberOfFrames)
{
	int i;
	AudioBufferList *list;
	list = (AudioBufferList *)calloc(1, sizeof(AudioBufferList) + channelsPerFrame * sizeof(AudioBuffer));
	if (list == NULL)
		return NULL;
	list->mNumberBuffers = channelsPerFrame;  /*  Assumes non-interleaved stream  */
	for(i = 0; i < channelsPerFrame; i++) {
		list->mBuffers[i].mNumberChannels = 1;  /*  Assumes non-interleaved stream  */
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
		//		fprintf(stderr, "firstInputTime = %f\n", (double)audio->firstInputTime);
	}
	//	fprintf(stderr, "inputTimeStamp = %f\n", (double)inTimeStamp->mSampleTime);
	
	/*  Render into audio buffer  */
	err = AudioUnitRender(info->unit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, info->bufferList);
	if (err != noErr) {
//		fprintf(stderr, "AudioUnitRender() failed with error %d\n", (int)err);
		return err;
	}
	
	/*  Write to ring buffer  */
	err = MDRingBufferStore(info->ring, info->bufferList, inNumberFrames, (MDSampleTime)inTimeStamp->mSampleTime);
	if (err != noErr) {
//		fprintf(stderr, "MDRingBufferStore() failed with error %d\n", (int)err);
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
	
//	{ static int count = 0; if (++count == 100) { fprintf(stderr, "sMDAudioPassProc called at %f, ioData->mNumberBuffers = %d\n", (double)inTimeStamp->mSampleTime, (int)ioData->mNumberBuffers); count = 0; } }

	if (info->firstInputTime < 0) {
		/*  The input has not arrived yet  */
		sMakeBufferSilent(ioData);
		return noErr;
	}
	/*	if ((err = AudioDeviceGetCurrentTime(This->mInputDevice.mID, &inTS)) != 0) {
	 MakeBufferSilent(ioData);
	 return noErr;
	 }
	 
	 CHECK_ERR(AudioDeviceGetCurrentTime(This->mOutputDevice.mID, &outTS)); */
	
	//	fprintf(stderr, "outputTimeStamp = %f\n", (double)inTimeStamp->mSampleTime);
	
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
	
	{ static int count = 0; if (++count == 100) { dprintf(3, "sMDAudioRecordProc called at %f, ioData->mNumberBuffers = %d\n", (double)inTimeStamp->mSampleTime, (int)ioData->mNumberBuffers); count = 0; } }
	
	/*  Render into audio buffer  */
	err = AudioUnitRender(gAudio->mixerUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData);
	if (err != noErr) {
		dprintf(0, "AudioUnitRender() failed with error %d in sMDAudioRecordProc\n", (int)err);
		return err;
	}
	
	/*  Write to file  */
	if (gAudio->isRecording) {
		err = ExtAudioFileWriteAsync(gAudio->audioFile, inNumberFrames, ioData);
		if (err != noErr) {
			dprintf(0, "ExtAudioFileWrite() failed with error %d in sMDAudioRecordProc\n", (int)err);
			return err;
		}
	}

	if (err != noErr) {
	//	fprintf(stderr, "sMDAudioRecordProc() failed with error %d\n", (int)err);
		return err;
	}
	
	if (!gAudio->isAudioThruEnabled)
		return 1;  /*  Discard the input data  */

	return noErr;
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
                address.mScope = (isInput ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput);
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
sMDAudioUpdateSoftwareDeviceInfo(void)
{
	ComponentDescription ccd, fcd;
	Component cmp = NULL;
	Handle pName;
	char *cName;
	int len, n, i;
	UInt32 propSize;
	MDAudioMusicDeviceInfo info, *ip;
	OSStatus err;
	MDStatus status = kMDNoError;

	if (gAudio->musicDeviceInfos == NULL) {
		gAudio->musicDeviceInfos = MDArrayNewWithDestructor(sizeof(MDAudioMusicDeviceInfo), sMDAudioMusicDeviceInfoDestructor);
		if (gAudio->musicDeviceInfos == NULL) {
			return kMDErrorOutOfMemory;
		}
	}
	
	memset(&fcd, 0, sizeof(fcd));
	fcd.componentType = kAudioUnitType_MusicDevice;
	pName = NewHandle(0);
	n = 0;
	while ((cmp = FindNextComponent(cmp, &fcd)) != 0) {
		ComponentInstance ci;
		
		/*  Get the component information  */
		GetComponentInfo(cmp, &ccd, pName, NULL, NULL);
		HLock(pName);
		cName = *pName;
		len = (unsigned char)(*cName++);
		memset(&info, 0, sizeof(info));
		info.code = (((UInt64)ccd.componentSubType) << 32) + ((UInt64)ccd.componentManufacturer);
		info.name = (char *)malloc(len + 1);
		strncpy(info.name, cName, len);
		info.name[len] = 0;
		HUnlock(pName);
		for (i = 0; (ip = MDArrayFetchPtr(gAudio->musicDeviceInfos, i)) != NULL; i++) {
			if (ip->code == info.code && strncmp(ip->name, cName, len) == 0) {
				free(info.name);
				info.name = NULL;
				break;
			}
		}
		if (ip != NULL)
			continue;  /*  This device is already known  */
		
		MyAppCallback_startupMessage("Loading %s...", info.name);
		
		/*  Get the audio output format  */
		err = OpenAComponent(cmp, &ci);
		if (err == noErr) {
			propSize = sizeof(MDAudioFormat);
			err = AudioUnitGetProperty(ci, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &info.format, &propSize);
		} else {
			ci = NULL;
		}
		if (err == noErr) {
			propSize = sizeof(MDAudioFormat);
			err = AudioUnitGetProperty(ci, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &info.format, &propSize);
		}
		if (err == noErr) {
			err = AudioUnitGetPropertyInfo(ci, kAudioUnitProperty_GetUIComponentList, kAudioUnitScope_Global, 0, &propSize, NULL);
			if (err == noErr && propSize > 0)
				info.hasCustomView = 1;
			else {
				info.hasCustomView = 0;
				err = noErr;
			}
		}
		if (err == noErr) {
			status = MDArrayInsert(gAudio->musicDeviceInfos, MDArrayCount(gAudio->musicDeviceInfos), 1, &info);
		} else {
			status = kMDErrorCannotSetupAudio;
		}
		if (ci != NULL)
			CloseComponent(ci);
		if (status == kMDNoError)
			n++;
		else {
			free(info.name);
			info.name = NULL;
			break;
		}
	}
	DisposeHandle(pName);
	MyAppCallback_startupMessage("");
	return status;
}

MDStatus
MDAudioUpdateDeviceInfo(void)
{
	MDStatus err;
	err = sMDAudioUpdateHardwareDeviceInfo();
	if (err != kMDNoError)
		return err;
	return sMDAudioUpdateSoftwareDeviceInfo();
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

MDAudioIOStreamInfo *
MDAudioGetIOStreamInfoAtIndex(int idx)
{
	if (idx < 0 || idx >= kMDAudioNumberOfStreams)
		return NULL;
	return &(gAudio->ioStreamInfos[idx]);
}

MDStatus
MDAudioSelectIOStreamDevice(int idx, int deviceIndex)
{
	OSStatus result = noErr;
	MDAudioIOStreamInfo *ip;
	MDAudioDeviceInfo *dp = NULL;
	MDAudioMusicDeviceInfo *mp = NULL;
	MDStatus sts;
	AudioDeviceID audioDeviceID;
	AURenderCallbackStruct callback;
	unsigned char midiSetupChanged = 0;

	ip = MDAudioGetIOStreamInfoAtIndex(idx);
	if (ip == NULL)
		return kMDErrorCannotSetupAudio;
	
	/*  No change required?  */
	if (ip->deviceIndex == deviceIndex && ip->busIndex == (idx % kMDAudioFirstIndexForOutputStream))
		return kMDNoError;

	CHECK_ERR(result, AUGraphStop(gAudio->graph));
	
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
					gAudio->isAudioThruEnabled = 1;
					ip->busIndex = (idx % kMDAudioFirstIndexForOutputStream);
					ip->deviceID = (UInt64)(dp->deviceID);
					ip->deviceIndex = deviceIndex;
				} else {
					gAudio->isAudioThruEnabled = 0;
					ip->busIndex = -1;
				}
			} else {
				gAudio->isAudioThruEnabled = 1;
				ip->busIndex = (idx % kMDAudioFirstIndexForOutputStream);
				ip->deviceIndex = deviceIndex;
			}
		}
	} else {
		/*  Input stream  */
		UInt64 newDeviceID;
		AudioComponentDescription desc;
		if (deviceIndex >= kMDAudioMusicDeviceIndexOffset) {
			mp = MDAudioMusicDeviceInfoAtIndex(deviceIndex - kMDAudioMusicDeviceIndexOffset);
			newDeviceID = (mp != NULL ? mp->code : kMDAudioMusicDeviceUnknown);
		} else {
			dp = MDAudioDeviceInfoAtIndex(deviceIndex, 1);
			newDeviceID = (dp != NULL ? (UInt64)(dp->deviceID) : kMDAudioMusicDeviceUnknown);
		}
		/*  Disable the current input  */
		if (ip->deviceID != kMDAudioMusicDeviceUnknown) {
			if (ip->deviceIndex >= kMDAudioMusicDeviceIndexOffset) {
				/*  Music Device  */
				CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, ip->converterNode, 0));
				CHECK_ERR(result, AUGraphDisconnectNodeInput(gAudio->graph, gAudio->mixer, idx));
				CHECK_ERR(result, AUGraphRemoveNode(gAudio->graph, ip->converterNode));
				CHECK_ERR(result, AUGraphRemoveNode(gAudio->graph, ip->node));
			/*  It looks like the component is automatically closed when the AUNode is removed  */
			/*	CHECK_ERR(result, (OSStatus)CloseComponent(ip->unit)); */
				ip->node = ip->converterNode = 0;
				ip->unit = ip->converterUnit = NULL;
				if (ip->midiControllerName != NULL) {
					free(ip->midiControllerName);
					ip->midiControllerName = NULL;
				}
				if (ip->midiCon != NULL) {
					CHECK_ERR(result, AUMIDIControllerDispose(ip->midiCon));
					ip->midiCon = NULL;
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
				/*  Audio Device  */
				/*  Disable callback for the mixer input  */
				callback.inputProc = NULL;
				callback.inputProcRefCon = NULL;
				CHECK_ERR(result, AudioUnitSetProperty(gAudio->mixerUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, idx, &callback, sizeof(AURenderCallbackStruct)));
				/*  Dispose the input AudioUnit  */
				CHECK_ERR(result, (OSStatus)CloseComponent(ip->unit));
			}
			ip->deviceID = kMDAudioMusicDeviceUnknown;
			ip->node = 0;
			ip->unit = NULL;
			ip->deviceIndex = -1;
			ip->busIndex = -1;
		}
		if (newDeviceID != kMDAudioMusicDeviceUnknown) {
			/*  Enable the new input  */
			if (deviceIndex >= kMDAudioMusicDeviceIndexOffset) {
				int i, n, len;
				MDAudioIOStreamInfo *ip2;
				CFStringRef str;
				/*  Music Device  */
				/*  Create input node  */
				desc.componentType = kAudioUnitType_MusicDevice;
				desc.componentSubType = (UInt32)(newDeviceID >> 32);
				desc.componentManufacturer = (UInt32)(newDeviceID);
				desc.componentFlags = desc.componentFlagsMask = 0;
				CHECK_ERR(result, AUGraphAddNode(gAudio->graph, &desc, &ip->node));
				/*  Create converter  */
				desc.componentType = kAudioUnitType_FormatConverter;
				desc.componentSubType = kAudioUnitSubType_AUConverter;
				desc.componentManufacturer = kAudioUnitManufacturer_Apple;
				desc.componentFlags = desc.componentFlagsMask = 0;
				CHECK_ERR(result, AUGraphAddNode(gAudio->graph, &desc, &ip->converterNode));
				/*  Connect input node -> converter -> mixer  */
				CHECK_ERR(result, AUGraphOpen(gAudio->graph));
				CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, ip->node, 0, ip->converterNode, 0));
				CHECK_ERR(result, AUGraphConnectNodeInput(gAudio->graph, ip->converterNode, 0, gAudio->mixer, idx));
				ip->deviceID = newDeviceID;
				CHECK_ERR(result, AUGraphNodeInfo(gAudio->graph, ip->node, NULL, &ip->unit));
				CHECK_ERR(result, AUGraphNodeInfo(gAudio->graph, ip->converterNode, NULL, &ip->converterUnit));
				/*  Input and output audio format for the converter  */
				CHECK_ERR(result, AudioUnitSetProperty(ip->converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &mp->format, sizeof(AudioStreamBasicDescription)));
				CHECK_ERR(result, AudioUnitSetProperty(ip->converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &gAudio->preferredFormat, sizeof(AudioStreamBasicDescription)));
				/*  Create the MIDI controller  */
				len = strlen(mp->name) + 5;
				ip->midiControllerName = (char *)malloc(len);
				strcpy(ip->midiControllerName, mp->name);
				/*  Check the duplicate  */
				for (i = 0, n = 2; i < kMDAudioNumberOfInputStreams; i++) {
					ip2 = MDAudioGetIOStreamInfoAtIndex(i);
					if (ip == ip2 || ip2->midiControllerName == NULL)
						continue;
					if (strcmp(ip->midiControllerName, ip2->midiControllerName) == 0) {
						snprintf(ip->midiControllerName, len, "%s %d", mp->name, n);
						n++;
						i = -1;
						continue;
					}
				}
				str = CFStringCreateWithCString(NULL, ip->midiControllerName, kCFStringEncodingUTF8);
				result = AUMIDIControllerCreate(str, &ip->midiCon);
				if (result == noErr) {
					result = AUMIDIControllerMapChannelToAU(ip->midiCon, -1, ip->unit, -1, 0);
				}
				CFRelease(str);
				midiSetupChanged = 1;
			} else {
				/*  Audio Device  */
				/*  Create HAL input unit (not connected to AUGraph)  */
				/*  Cf. Apple Technical Note 2091  */
				AudioComponent comp;
				UInt32 unum;
				AURenderCallbackStruct callback;
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
				/*  Set the HAL AU output format to the canonical format   */
				CHECK_ERR(result, AudioUnitSetProperty(ip->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &gAudio->preferredFormat, sizeof(AudioStreamBasicDescription)));
				/*  Set the AU callback function (HAL input device)  */
				callback.inputProc = sMDAudioInputProc;
				callback.inputProcRefCon = ip;
				CHECK_ERR(result, AudioUnitSetProperty(ip->unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, sizeof(AURenderCallbackStruct)));
				/*  Set the AU callback function (mixer)  */
				callback.inputProc = sMDAudioPassProc;
				callback.inputProcRefCon = ip;
				CHECK_ERR(result, AudioUnitSetProperty(gAudio->mixerUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, idx, &callback, sizeof(AURenderCallbackStruct)));
				/*  Set the input device  */
				audioDeviceID = (AudioDeviceID)newDeviceID;
				CHECK_ERR(result, AudioUnitSetProperty(ip->unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &audioDeviceID, sizeof(AudioDeviceID)));
				/*  Reallocate buffer list  */
				ip->bufferSizeFrames = dp->bufferSizeFrames;  /*  The buffer size of the underlying audio device; NOTE: dp must be alive until here!  */
				ip->bufferList = sMDAudioAllocateMyBufferList(gAudio->preferredFormat.mChannelsPerFrame, gAudio->preferredFormat.mBytesPerFrame, ip->bufferSizeFrames);
				
				/*  Reallocate ring buffer  */
				ip->ring = MDRingBufferNew();
				MDRingBufferAllocate(ip->ring, gAudio->preferredFormat.mChannelsPerFrame, gAudio->preferredFormat.mBytesPerFrame, ip->bufferSizeFrames * 20);
				
				ip->firstInputTime = ip->firstOutputTime = -1;
				/*  Initialize and start the AUHAL  */
				CHECK_ERR(result, AudioUnitInitialize(ip->unit));
				CHECK_ERR(result, AudioOutputUnitStart(ip->unit));
			}
			ip->deviceID = newDeviceID;
			ip->deviceIndex = deviceIndex;
			ip->busIndex = (idx % kMDAudioNumberOfOutputStreams);
		}
	}
exit:
	sts = (result == noErr ? kMDNoError : kMDErrorCannotSetupAudio);
	if (sts == kMDNoError && midiSetupChanged)
		MDPlayerNotificationCallback();
	result = AUGraphStart(gAudio->graph);
	return (sts == kMDNoError && sts == noErr ? kMDNoError : kMDErrorCannotSetupAudio);
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

#if 0
MDStatus
MDAudioSelectInOutDeviceAtIndices(int inputIndex, int outputIndex)
{
	MDAudioDeviceInfo *inInfop, *outInfop;
	OSStatus err;
	UInt32 size;
	if (inputIndex == -2) {
		/*  Disable input  */
		CHECK_ERR(err, AudioOutputUnitStop(gAudio->inputUnit));
		gAudio->isInputRunning = 0;
		gAudio->firstInputTime = -1;
	}
	outInfop = MDAudioDeviceInfoAtIndex(outputIndex, 0);
	inInfop = MDAudioDeviceInfoAtIndex(inputIndex, 1);
	if (inInfop != NULL || outInfop != NULL) {

		if (gAudio->isRunning)
			CHECK_ERR(err, AUGraphStop(gAudio->graph));
		if (gAudio->isInputRunning)
			CHECK_ERR(err, AudioOutputUnitStop(gAudio->inputUnit));

		if (inInfop != NULL) {

			/*  Set the input device  */
			CHECK_ERR(err, AudioUnitSetProperty(gAudio->inputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &(inInfop->deviceID), sizeof(AudioDeviceID)));			

			/*  Copy the device info to internal cache  */
			gAudio->inputDeviceInfoCache = *inInfop;
			gAudio->inputDeviceInfoCache.name = NULL;

			/*  Reallocate buffer list  */
			if (gAudio->inputBufferList != NULL)
				sMDAudioReleaseMyBufferList(gAudio->inputBufferList);
			gAudio->inputBufferList = sMDAudioAllocateMyBufferList(gAudio->preferredFormat.mChannelsPerFrame, gAudio->preferredFormat.mBytesPerFrame, inInfop->bufferSizeFrames);
			
			/*  Reallocate ring buffer  */
			if (gAudio->ring != NULL)
				MDRingBufferDeallocate(gAudio->ring);
			else gAudio->ring = MDRingBufferNew();
			MDRingBufferAllocate(gAudio->ring, gAudio->preferredFormat.mChannelsPerFrame, gAudio->preferredFormat.mBytesPerFrame, inInfop->bufferSizeFrames * 20);

			gAudio->firstInputTime = -1;

		}

		if (outInfop != NULL) {

			/*  Set the output device  */
			CHECK_ERR(err, AudioUnitSetProperty(gAudio->outputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &(outInfop->deviceID), sizeof(AudioDeviceID)));			

			/*  Match the format with mixer  */
			CHECK_ERR(err, AudioUnitSetProperty(gAudio->outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &gAudio->preferredFormat, sizeof(AudioStreamBasicDescription)));

			/*  Copy the device info to internal cache  */
			gAudio->outputDeviceInfoCache = *outInfop;
			gAudio->outputDeviceInfoCache.name = NULL;

			gAudio->firstOutputTime = -1;
		}
		
		if (gAudio->isRunning) {
			CHECK_ERR(err, AUGraphStart(gAudio->graph));
			if (inInfop != NULL || gAudio->isInputRunning) {
				CHECK_ERR(err, AudioOutputUnitStart(gAudio->inputUnit));
				gAudio->isInputRunning = 1;
			}
		}
	}
	return 0;
exit:
	return kMDErrorCannotSetupAudio;
}

MDStatus
MDAudioGetInOutDeviceIndices(int *inputIndex, int *outputIndex)
{
	OSStatus err;
	AudioDeviceID deviceID;
	int i, idx, isInput;
	MDAudioDeviceInfo *infop;
	UInt32 size;

	if (gAudio == NULL)
		return kMDErrorCannotSetupAudio;
	
	for (isInput = 0; isInput <= 1; isInput++) {
		if ((isInput ? inputIndex : outputIndex) == NULL)
			continue;
		if (isInput && gAudio->isInputRunning == 0) {
			*inputIndex = -1;
			continue;
		}
		size = sizeof(AudioDeviceID);
		CHECK_ERR(err, AudioUnitGetProperty(
											(isInput ? gAudio->inputUnit : gAudio->outputUnit),
											kAudioOutputUnitProperty_CurrentDevice,
											kAudioUnitScope_Global, 
											0, &deviceID, &size));
		idx = -1;
		for (i = 0; (infop = MDAudioDeviceInfoAtIndex(i, isInput)) != NULL; i++) {
			if (infop->deviceID == deviceID) {
				idx = i;
				break;
			}
		}
		if (isInput) {
			if (inputIndex != NULL)
				*inputIndex = idx;
		} else {
			if (outputIndex != NULL)
				*outputIndex = idx;
		}
	}
	return kMDNoError;
exit:
	return kMDErrorCannotSetupAudio;
}
#endif

#pragma mark ====== Start/Stop Audio input/output ======

#if 0
static char *
sOSTypeToString(OSType type, char *buf)
{
	UInt32 ui = (UInt32)type;
	buf[0] = (ui >> 24);
	buf[1] = (ui >> 16);
	buf[2] = (ui >> 8);
	buf[3] = ui;
	buf[4] = 0;
	return buf;
}

static void
sMDAudioListMusicDevice(void)
{
	ComponentDescription ccd, fcd;
	Component cmp = NULL;
	Handle pName;
	char *cName;
	int len, n;
	char buf[256], type1[6], type2[6];
	memset(&fcd, 0, sizeof(fcd));
	fcd.componentType = kAudioUnitType_MusicDevice;
	pName = NewHandle(0);
	n = 0;
	while((cmp = FindNextComponent(cmp, &fcd)) != 0) {
		GetComponentInfo(cmp, &ccd, pName, NULL, NULL);
		HLock(pName);
		cName = *pName;
		len = (unsigned char)(*cName++);
		strncpy(buf, cName, len);
		buf[len] = 0;
		fprintf(stderr, "device %d: %s\n", n, buf);
		fprintf(stderr, "  subtype = \'%s\', manufacturer = \'%s\'\n",
				sOSTypeToString(ccd.componentSubType, type1), sOSTypeToString(ccd.componentManufacturer, type2));
		n++;
		HUnlock(pName);
	}
	DisposeHandle(pName);
}

extern void MDAudioCheckAUViewCallback(AudioUnit);

static OSStatus
sAudioInitializeTest(void)
{
	AUGraph gGraph;
	AUNode gSynth, gOutput;
	MusicDeviceComponent gUnit;
	AUMIDIControllerRef gMIDICon;
	
	ComponentDescription desc;
	OSStatus result;
	require_noerr(result = NewAUGraph(&gGraph), failed);
	desc.componentType = kAudioUnitType_MusicDevice;
	//	desc.componentSubType = kAudioUnitSubType_DLSSynth;
	//	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	desc.componentSubType = FOUR_CHAR_CODE('Nik4');
	desc.componentManufacturer = FOUR_CHAR_CODE('-NI-');
	//	 desc.componentSubType = FOUR_CHAR_CODE('PH10');
	//	 desc.componentManufacturer = FOUR_CHAR_CODE('ikm_');
	desc.componentFlags = desc.componentFlagsMask = 0;
	require_noerr(result = AUGraphNewNode(gGraph, &desc, 0, NULL, &gSynth), failed);
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_DefaultOutput;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;	
	require_noerr(result = AUGraphNewNode(gGraph, &desc, 0, NULL, &gOutput), failed);
	require_noerr(result = AUGraphConnectNodeInput(gGraph, gSynth, 0, gOutput, 0), failed);
	require_noerr(result = AUGraphOpen(gGraph), failed);	
	require_noerr(result = AUGraphGetNodeInfo(gGraph, gSynth, NULL, NULL, NULL, &gUnit), failed);
	require_noerr(result = AUMIDIControllerCreate(CFSTR("Virtual Synth"), &gMIDICon), failed);
	require_noerr(result = AUMIDIControllerMapChannelToAU(gMIDICon, -1, gUnit, -1, 0), failed);
	require_noerr(result = AUGraphInitialize(gGraph), failed);	
	require_noerr(result = AUGraphStart(gGraph), failed);
	//	require_noerr(result = [self openCarbonUIForAudioUnit:gUnit], failed);
	MDAudioCheckAUViewCallback(gUnit);
failed:
	fprintf(stderr, "result = %d\n", (int)result);
	return result;
}
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
	MDAudioFormatSetCanonical(&gAudio->preferredFormat, 44100.0, 2, 0);

	/*  Initialize IOStreamInfo  */
	for (i = 0; i < kMDAudioNumberOfStreams; i++) {
		MDAudioIOStreamInfo *ip = &(gAudio->ioStreamInfos[i]);
		ip->deviceIndex = -1;
		ip->busIndex = -1;
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

	/*  Set the canonical format to mixer and output units  */
	CHECK_ERR(err, AudioUnitSetProperty(gAudio->outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &gAudio->preferredFormat, sizeof(AudioStreamBasicDescription)));
	CHECK_ERR(err, AudioUnitSetProperty(gAudio->mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Global, 0, &gAudio->preferredFormat, sizeof(AudioStreamBasicDescription)));
	
	/*  Set the AU callback function for the output unit  */
	/*  (Read output from the mixer and pass to the output _and_ record to the file)  */
	callback.inputProc = sMDAudioRecordProc;
	callback.inputProcRefCon = &(gAudio->ioStreamInfos[kMDAudioFirstIndexForOutputStream]);
	CHECK_ERR(err, AudioUnitSetProperty(gAudio->outputUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(AURenderCallbackStruct)));
	
	/*  Enable metering for the stereo mixer  */
	unum = 1;
	CHECK_ERR(err, AudioUnitSetProperty(gAudio->mixerUnit, kAudioUnitProperty_MeteringMode, kAudioUnitScope_Global, 0, &unum, sizeof(UInt32)));
	
	CHECK_ERR(err, AUGraphInitialize(gAudio->graph));	
	CHECK_ERR(err, AUGraphStart(gAudio->graph));


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
	CHECK_ERR(err, AUGraphStop(gAudio->graph));	
	CHECK_ERR(err, AUGraphClose(gAudio->graph));
	gAudio->graph = NULL;
	return kMDNoError;
exit:
	return kMDErrorCannotSetupAudio;
}

MDStatus
MDAudioGetMixerBusAttributes(int idx, float *outPan, float *outVolume, float *outAmpLeft, float *outAmpRight, float *outPeakLeft, float *outPeakRight)
{
	OSStatus err;
	Float32 f32;
	int scope;
	if (idx >= 0 && idx < kMDAudioNumberOfInputStreams) {
		scope = kAudioUnitScope_Input;
	} else if (idx >= kMDAudioFirstIndexForOutputStream && idx < kMDAudioNumberOfStreams) {
		idx -= kMDAudioFirstIndexForOutputStream;
		scope = kAudioUnitScope_Output;
	} else return kMDErrorCannotSetupAudio;
	if (scope == kAudioUnitScope_Input) {
		CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_Pan, scope, idx, &f32));
	} else f32 = 0.5;
	if (outPan != NULL)
		*outPan = f32;	
	CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_Volume, scope, idx, &f32));
	if (outVolume != NULL)
		*outVolume = f32;
	CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_PostAveragePower, scope, idx, &f32));
	if (outAmpLeft != NULL)
		*outAmpLeft = f32;
	CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_PostAveragePower + 1, scope, idx, &f32));
	if (outAmpRight != NULL)
		*outAmpRight = f32;
	CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_PostPeakHoldLevel, scope, idx, &f32));
	if (outPeakLeft != NULL)
		*outPeakLeft = f32;
	CHECK_ERR(err, AudioUnitGetParameter(gAudio->mixerUnit, kStereoMixerParam_PostPeakHoldLevel + 1, scope, idx, &f32));
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
	int scope;
	if (idx >= 0 && idx < kMDAudioNumberOfInputStreams) {
		scope = kAudioUnitScope_Input;
	} else if (idx >= kMDAudioFirstIndexForOutputStream && idx < kMDAudioNumberOfStreams) {
		idx -= kMDAudioFirstIndexForOutputStream;
		scope = kAudioUnitScope_Output;
	} else return kMDErrorCannotSetupAudio;
	CHECK_ERR(err, AudioUnitSetParameter(gAudio->mixerUnit, kStereoMixerParam_Volume, scope, idx, f32, 0));
	return kMDNoError;
exit:
	return kMDErrorCannotSetupAudio;
}

MDStatus
MDAudioSetMixerPan(int idx, float pan)
{
	OSStatus err;
	Float32 f32 = pan;
	int scope;
	if (idx >= 0 && idx < kMDAudioNumberOfInputStreams) {
		scope = kAudioUnitScope_Input;
	} else if (idx >= kMDAudioFirstIndexForOutputStream && idx < kMDAudioNumberOfStreams) {
		idx -= kMDAudioFirstIndexForOutputStream;
		scope = kAudioUnitScope_Output;
	} else return kMDErrorCannotSetupAudio;
	CHECK_ERR(err, AudioUnitSetParameter(gAudio->mixerUnit, kStereoMixerParam_Pan, scope, idx, f32, 0));
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

MDStatus
MDAudioPrepareRecording(const char *filename, const MDAudioFormat *format, int audioFileType)
{
	OSStatus err;
	FSRef parentDir;
	CFStringRef filenameStr;
	const char *p;
	
	if (gAudio->isRecording)
		return kMDErrorCannotSetupAudio;
	
	/*  Prepare FSRef/CFStringRef representation of the filename  */
	if ((p = strrchr(filename, '/')) == NULL) {
		char buf[MAXPATHLEN];
		getcwd(buf, sizeof buf);
		err = FSPathMakeRef((unsigned char *)buf, &parentDir, NULL);
		if (err != noErr)
			return kMDErrorCannotSetupAudio;
		filenameStr = CFStringCreateWithCString(NULL, p, kCFStringEncodingUTF8);
	} else {
		char *pp;
		pp = malloc(p - filename + 1);
		strncpy(pp, filename, p - filename);
		pp[p - filename] = 0;
		err = FSPathMakeRef((unsigned char *)pp, &parentDir, NULL);
		free(pp);
		if (err != noErr)
			return kMDErrorCannotSetupAudio;
		filenameStr = CFStringCreateWithCString(NULL, p + 1, kCFStringEncodingUTF8);
	}
	
	/*  Create a new audio file  */
	err = ExtAudioFileCreateNew(&parentDir, filenameStr, audioFileType, format, NULL, &(gAudio->audioFile));
	if (err != noErr)
		return kMDErrorCannotSetupAudio;

	/*  Set the client data format to the canonical one (i.e. the format the mixer handles) */
	err = ExtAudioFileSetProperty(gAudio->audioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &gAudio->preferredFormat);
	if (err != noErr)
		return kMDErrorCannotSetupAudio;

/*	// If we're recording from a mono source, setup a simple channel map to split to stereo
	if (fDeviceFormat.mChannelsPerFrame == 1 && fOutputFormat.mChannelsPerFrame == 2)
	{
		// Get the underlying AudioConverterRef
		UInt32 size = sizeof(AudioConverterRef);
		err = ExtAudioFileGetProperty(fOutputAudioFile, kExtAudioFileProperty_AudioConverter, &size, &conv);
		if (conv)
		{
			// This should be as large as the number of output channels,
			// each element specifies which input channel's data is routed to that output channel
			SInt32 channelMap[] = { 0, 0 };
			err = AudioConverterSetProperty(conv, kAudioConverterChannelMap, 2*sizeof(SInt32), channelMap);
		}
	}
*/

	/*  Initialize AudioFile IO  */
	err = ExtAudioFileWriteAsync(gAudio->audioFile, 0, NULL);
	if (err != noErr)
		return kMDErrorCannotSetupAudio;

	return kMDNoError;
}

MDStatus
MDAudioStartRecording(void)
{
/*	MDStatus sts; */
	if (gAudio->isRecording)
		return kMDErrorCannotSetupAudio;
/*	if (sts != kMDNoError)
		return sts; */
	gAudio->isRecording = 1;
	return kMDNoError;
}

MDStatus
MDAudioStopRecording(void)
{
	OSStatus err;
	if (!gAudio->isRecording)
		return kMDErrorCannotProcessAudio;
	gAudio->isRecording = 0;
	CHECK_ERR(err, ExtAudioFileDispose(gAudio->audioFile));
	gAudio->audioFile = NULL;
/*	if (!gAudio->isAudioThruEnabled) {
		MDStatus sts = MDAudioStopInput();
		if (sts != kMDNoError)
			return sts;
	} */
	return kMDNoError;
exit:
	return kMDErrorCannotProcessAudio;
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


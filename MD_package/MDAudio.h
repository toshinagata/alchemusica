/*
 *  MDAudio.h
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 08/01/06.
 *  Copyright (c) 2008-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#ifndef __MDAudio__
#define __MDAudio__

#include <CoreAudio/CoreAudio.h>
#include <AudioToolBox/AudioToolbox.h>
#include <AudioUnit/AudioUnit.h>
#include "MDAudioUtility.h"

typedef struct MDAudio MDAudio;

#define CHECK_ERR(var, funcall) do { var = (funcall); if (var) { MDAudioShowError(var, __FILE__, __LINE__); goto exit; } } while (0)

//  CoreAudio specific
typedef AudioStreamBasicDescription MDAudioFormat;
typedef AudioDeviceID MDAudioDeviceID;

enum {
	kMDAudioDeviceUnknown = kAudioDeviceUnknown
};

#define	kMDAudioMusicDeviceUnknown ((UInt64)0)

enum {
	kMDAudioFileAIFFType = kAudioFileAIFFType,
	kMDAudioFileWAVType = kAudioFileWAVEType
};

/*  Cached information for the hardware audio devices  */
typedef struct MDAudioDeviceInfo {
	char *name;  /*  malloc'ed  */
	MDAudioDeviceID deviceID;
	SInt16 nChannels;
	SInt16 flags;   /*  For internal use  */
	UInt32 safetyOffset;
	UInt32 bufferSizeFrames;
	MDAudioFormat format;
} MDAudioDeviceInfo;

enum {
    kMDAudioHasCocoaView = 1,
    kMDAudioHasCarbonView = 2
};

/*  Cached information for Music Devices (software synthesizers)  */
/*  Also used for audio effects  */
typedef struct MDAudioMusicDeviceInfo {
	UInt64 code;  /*  SubType and Manufacturer  */
	char *name;   /*  malloc'ed  */
	MDAudioFormat format;
	unsigned char hasCustomView;
    unsigned char acceptsCanonicalFormat;  /*  For effects  */
} MDAudioMusicDeviceInfo;

#define kMDAudioNumberOfInputStreams 40
#define kMDAudioNumberOfOutputStreams 1
#define kMDAudioNumberOfStreams (kMDAudioNumberOfInputStreams + kMDAudioNumberOfOutputStreams)
#define kMDAudioFirstIndexForOutputStream kMDAudioNumberOfInputStreams
#define kMDAudioMusicDeviceIndexOffset 1000

#define kMDAudioMaxMIDIBytesToSendPerDevice 4096
#define kMDAudioMIDIBufferSize (kMDAudioMaxMIDIBytesToSendPerDevice * 8)

/*  Audio Effect Instance  */
typedef struct MDAudioEffect {
    char *name;  /*  malloc'ed  */
    float xpos;  /*  X position in the layout view  */
    float width; /*  Width in the layout view  */
    int effectDeviceIndex;  /*  Index to gAudio->effectDeviceInfos  */
    AudioUnit unit;  /*  Effect unit  */
    AUNode node;     /*  AUGraph node containing the effect unit  */
    AudioUnit converterUnit;  /*  Converter unit (optional)  */
    AUNode converterNode;
} MDAudioEffect;

/*  Audio Effect Chain (for a single stereo signal)  */
typedef struct MDAudioEffectChain {
    AudioUnit converterUnit;  /*  Converter unit (used at the mixer input if necessary) */
    AUNode converterNode;
    int alive;   /*  Non-zero if this chain is working  */
    int neffects;
    MDAudioEffect *effects;
} MDAudioEffectChain;

/*  Cached information for audio input (up to 40) and output (one). */
typedef struct MDAudioIOStreamInfo {
	
	int deviceIndex;  /*  -1: none, 0-999: {input|output}DeviceInfos, 1000-: musicDeviceInfos  */
	int busIndex;     /*  The bus number (redundant, but useful in the callback)  */
	UInt64 deviceID;  /*  UInt64 for music device; AudioDeviceID for audio device  */

	AudioUnit unit;   /*  AUHAL or MusicDevice  */
	AUNode node;      /*  Node in the AUGraph  */
	AudioUnit converterUnit;  /*  Converter unit (for MusicDevice)  */
	AUNode converterNode;
    
    /*  Effects  */
    AudioUnit effectMixerUnit;  /*  Mixer for effect outputs (only for nchains>=2)  */
    AUNode effectMixerNode;
    int nchains;
    MDAudioEffectChain *chains;
    
	float pan;
	float volume;
    MDAudioFormat format;  /*  Audio format for the unit  */
	
	/*  for input AUHAL only  */
	AudioBufferList *bufferList;  /*  Buffer for getting audio signal from AUHAL  */
	MDRingBuffer *ring;           /*  Ring buffer for feeding the mixer input  */
	MDSampleTime firstInputTime;  /*  Time stamp for audio signal input  */
	MDSampleTime firstOutputTime; /*  Time stamp for audio siganl output  */
	MDSampleTime inToOutSampleOffset;  /*  Time stamp offset  */
	SInt32 bufferSizeFrames;      /*  buffer size  */

	/*  for MusicDevice only  */
	char *midiControllerName;  /*  malloc'ed  */
    unsigned char *midiBuffer; /*  Ring buffer for MIDI scheduling  */
    int32_t midiBufferWriteOffset;
    int32_t midiBufferReadOffset;
    int32_t sysexLength;
    unsigned char *sysexData;
    int32_t requestFlush;
} MDAudioIOStreamInfo;

MDStatus MDAudioInitialize(void);
MDStatus MDAudioDispose(void);
int MDAudioShowError(OSStatus sts, const char *file, int line);

//MDAudio *	MDAudioNew(void);
//void		MDAudioRelease(MDAudio *inAudio);

MDStatus    MDAudioUpdateDeviceInfo(void);
int         MDAudioDeviceCountInfo(int isInput);
MDAudioDeviceInfo *MDAudioDeviceInfoAtIndex(int idx, int isInput);
MDAudioDeviceInfo *MDAudioDeviceInfoForDeviceID(int deviceID, int isInput, int *deviceIndex);
MDAudioDeviceInfo *MDAudioDeviceInfoWithName(const char *name, int isInput, int *deviceIndex);
int         MDAudioMusicDeviceCountInfo(void);
MDAudioMusicDeviceInfo *MDAudioMusicDeviceInfoAtIndex(int idx);
MDAudioMusicDeviceInfo *MDAudioMusicDeviceInfoForCode(UInt64 code, int *outIndex);
int         MDAudioEffectDeviceCountInfo(void);
MDAudioMusicDeviceInfo *MDAudioEffectDeviceInfoAtIndex(int idx);
MDAudioMusicDeviceInfo *MDAudioEffectDeviceInfoForCode(UInt64 code, int *outIndex);

MDAudioIOStreamInfo *MDAudioGetIOStreamInfoAtIndex(int idx);
int MDAudioScheduleMIDIToStream(MDAudioIOStreamInfo *ip, UInt64 timeStamp, int length, unsigned char *midiData, int isSysEx);

/*  idx: 0-(kMDAudioNumberOfInputStreams-1)...input, kMDAudioFirstIndexForOutputStream...output */
/*  deviceIndex: -1: none, 0-999: {input|output}DeviceInfos, 1000-: musicDeviceInfos  */
MDStatus    MDAudioSelectIOStreamDevice(int idx, int deviceIndex);
MDStatus    MDAudioGetIOStreamDevice(int idx, int *outDeviceIndex);
MDStatus    MDAudioGetMixerBusAttributes(int idx, float *outPan, float *outVolume, float *outAmpLeft, float *outAmpRight, float *outPeakLeft, float *outPeakRight);
MDStatus    MDAudioSetMixerVolume(int idx, float volume);
MDStatus    MDAudioSetMixerPan(int idx, float pan);

MDStatus    MDAudioAppendEffectChain(int streamIndex);
MDStatus    MDAudioRemoveLastEffectChain(int streamIndex);
MDStatus    MDAudioChangeEffect(int streamIndex, int chainIndex, int effectIndex, int effectID, int insert);
MDStatus    MDAudioRemoveEffect(int streamIndex, int chainIndex, int effectIndex);

/*MDStatus	MDAudioStartInput(void);
MDStatus	MDAudioStopInput(void); */
/*MDStatus	MDAudioEnablePlayThru(int flag);
int			MDAudioIsPlayThruEnabled(void); */

MDStatus	MDAudioPrepareRecording(const char *filename, const MDAudioFormat *format, int audioFileType, UInt64 recordingDuration);
MDStatus	MDAudioStartRecording(void);
MDStatus	MDAudioStopRecording(void);
int         MDAudioIsRecording(void);

//MDStatus	MDAudioPrepareRecording(MDAudio *inAudio, MDAudioDeviceID deviceID, const char *filename, const MDAudioFormat *format, int audioFileType);
//MDStatus	MDAudioStartRecording(MDAudio *inAudio);
//MDStatus	MDAudioStop(MDAudio *inAudio);
//MDStatus	MDAudioStopRecording(MDAudio *inAudio);
//int         MDAudioIsRecording(MDAudio *inAudio);
//MDArray *	MDAudioGetDeviceInfo(int isInput);
//MDAudioDeviceID	MDAudioDeviceWithName(const char *name, int isInput);

void	MDAudioFormatSetCanonical(MDAudioFormat *fmt, float sampleRate, int nChannels, int interleaved);

#endif

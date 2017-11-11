/*
 *  MDPlayer_MacOSX.h
 *
 *  Created by Toshi Nagata on Sun Jul 01 2001.

   Copyright (c) 2000-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#ifndef __MDPlayer_MacOSX__
#define __MDPlayer_MacOSX__

#include "MDSequence.h"
#include "MDAudio.h"

typedef struct MetronomeInfoRecord {
	int32_t dev;
	int channel;
	int note1;
	int vel1;
	int note2;
	int vel2;
	char enableWhenPlay;
	char enableWhenRecord;
	int32_t duration;
} MetronomeInfoRecord;

extern MetronomeInfoRecord gMetronomeInfo;

typedef struct MDPlayer		MDPlayer;

typedef signed char			MDPlayerStatus;
enum {
	kMDPlayer_idle = 0,
	kMDPlayer_ready,
	kMDPlayer_playing,
	kMDPlayer_suspended,
	kMDPlayer_exhausted
};

//#define GetHostTimeInMDTimeType()	((MDTimeType)((AudioConvertHostTimeToNanos(AudioGetCurrentHostTime()) / 1000)))
#define ConvertMDTimeTypeToHostTime(tm)	AudioConvertNanosToHostTime((UInt64)(tm) * 1000)
#define ConvertHostTimeToMDTimeType(tm) ((MDTimeType)(AudioConvertHostTimeToNanos(tm) / 1000))
#define GetHostTimeInMDTimeType() ConvertHostTimeToMDTimeType(AudioGetCurrentHostTime())


/* -------------------------------------------------------------------
    MDPlayer functions
   -------------------------------------------------------------------  */

/*void		MDPlayerInitMIDIDevices(void); */

MDPlayer *	MDPlayerNew(MDSequence *inSequence);
void		MDPlayerRetain(MDPlayer *inPlayer);
void		MDPlayerRelease(MDPlayer *inPlayer);

MDStatus	MDPlayerSetSequence(MDPlayer *inPlayer, MDSequence *inSequence);
MDStatus	MDPlayerRefreshTrackDestinations(MDPlayer *inPlayer);
MDStatus	MDPlayerJumpToTick(MDPlayer *inPlayer, MDTickType inTick);
MDStatus	MDPlayerPreroll(MDPlayer *inPlayer, MDTickType inTick, int backtrack);
MDStatus	MDPlayerStart(MDPlayer *inPlayer);
MDStatus	MDPlayerStop(MDPlayer *inPlayer);
MDStatus	MDPlayerSuspend(MDPlayer *inPlayer);
MDStatus	MDPlayerStartRecording(MDPlayer *inPlayer);
MDStatus    MDPlayerSetRecordingStopTick(MDPlayer *inPlayer, MDTickType inTick);
MDStatus    MDPlayerStopRecording(MDPlayer *inPlayer);

MDPlayerStatus	MDPlayerGetStatus(MDPlayer *inPlayer);
int			MDPlayerIsRecording(MDPlayer *inPlayer);
MDPlayer *  MDPlayerRecordingPlayer(void);

MDTimeType	MDPlayerGetTime(MDPlayer *inPlayer);
MDTickType	MDPlayerGetTick(MDPlayer *inPlayer);

void		MDPlayerSetMIDIThruDeviceAndChannel(int32_t dev, int ch);
void        MDPlayerSetMIDIThruTranspose(int transpose);
void        MDPlayerSetCountOffSettings(MDPlayer *inPlayer, MDTimeType duration, MDTimeType bar, MDTimeType beat);
MDStatus	MDPlayerBacktrackEvents(MDPlayer *inPlayer, MDTickType inTick, const int32_t *inEventType, const int32_t *inEventTypeLastOnly);
int			MDPlayerSendRawMIDI(MDPlayer *player, const unsigned char *p, int size, int destDevice, MDTimeType scheduledTime);
void		MDPlayerRingMetronomeClick(MDPlayer *inPlayer, MDTimeType atTime, int isPrincipal);

void		MDPlayerReloadDeviceInformation(void);
int32_t		MDPlayerGetNumberOfDestinations(void);
MDStatus	MDPlayerGetDestinationName(int32_t dev, char *name, int32_t sizeof_name);
int32_t		MDPlayerGetDestinationNumberFromName(const char *name);
int32_t		MDPlayerGetDestinationUniqueID(int32_t dev);
int32_t		MDPlayerGetDestinationNumberFromUniqueID(int32_t uniqueID);
int32_t		MDPlayerGetNumberOfSources(void);
MDStatus	MDPlayerGetSourceName(int32_t dev, char *name, int32_t sizeof_name);
int32_t		MDPlayerGetSourceNumberFromName(const char *name);
//int32_t		MDPlayerGetSourceUniqueID(int32_t dev);
//int32_t		MDPlayerGetSourceNumberFromUniqueID(int32_t uniqueID);
int32_t        MDPlayerAddDestinationName(const char *name);
int32_t        MDPlayerAddSourceName(const char *name);

int         MDPlayerUpdatePatchNames(int32_t dev);
int         MDPlayerGetNumberOfPatchNames(int32_t dev);
int         MDPlayerGetPatchName(int32_t dev, int bank, int progno, char *name, int32_t sizeof_name);

int			MDPlayerGetRecordedEvents(MDPlayer *inPlayer, MDEvent **outEvent, int *outEventBufSiz);
void		MDPlayerClearRecordedEvents(MDPlayer *inPlayer);

/*MDAudio *	MDPlayerGetAudioPlayer(MDPlayer *inPlayer); */

/*  These are only for internal (and debugging) use. Use MDPlayerGetRecordedEvent() to retreave recorded data.  */
int			MDPlayerPutRecordingData(MDPlayer *inPlayer, MDTimeType timeStamp, int32_t size, const unsigned char *buf);
int			MDPlayerGetRecordingData(MDPlayer *inPlayer, MDTimeType *outTimeStamp, int32_t *outSize, unsigned char **outBuf, int32_t *outBufSize);

/*  Defined in MyAppController.m; will be called when any of the MIDI setup is modified  */
extern void MDPlayerNotificationCallback(void);

/*  Utility function  */
int my_usleep(uint32_t useconds);

#endif  /*  __MDPlayer_MacOSX__  */

/*
 *  MDPlayer_MacOSX.h
 *
 *  Created by Toshi Nagata on Sun Jul 01 2001.

   Copyright (c) 2000-2011 Toshi Nagata. All rights reserved.

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
	long dev;
	int channel;
	int note1;
	int vel1;
	int note2;
	int vel2;
	char enableWhenPlay;
	char enableWhenRecord;
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
MDStatus	MDPlayerStartRecording(MDPlayer *inPlayer);
MDStatus	MDPlayerStop(MDPlayer *inPlayer);
MDStatus    MDPlayerScheduleStopTick(MDPlayer *inPlayer, MDTickType inStopTick);
MDStatus    MDPlayerStopRecording(MDPlayer *inPlayer);
MDStatus	MDPlayerSuspend(MDPlayer *inPlayer);

MDPlayerStatus	MDPlayerGetStatus(MDPlayer *inPlayer);
int			MDPlayerIsRecording(MDPlayer *inPlayer);
MDPlayer *  MDPlayerRecordingPlayer(void);

MDTimeType	MDPlayerGetTime(MDPlayer *inPlayer);
MDTickType	MDPlayerGetTick(MDPlayer *inPlayer);

void		MDPlayerSetMIDIThruDeviceAndChannel(long dev, int ch);
MDStatus	MDPlayerBacktrackEvents(MDPlayer *inPlayer, const long *inEventType, const long *inEventTypeLastOnly);
int			MDPlayerSendRawMIDI(MDPlayer *player, const unsigned char *p, int size, int destDevice, MDTimeType scheduledTime);

void		MDPlayerReloadDeviceInformation(void);
long		MDPlayerGetNumberOfDestinations(void);
MDStatus	MDPlayerGetDestinationName(long dev, char *name, long sizeof_name);
long		MDPlayerGetDestinationNumberFromName(const char *name);
long		MDPlayerGetDestinationUniqueID(long dev);
long		MDPlayerGetDestinationNumberFromUniqueID(long uniqueID);
long		MDPlayerGetNumberOfSources(void);
MDStatus	MDPlayerGetSourceName(long dev, char *name, long sizeof_name);
long		MDPlayerGetSourceNumberFromName(const char *name);
long		MDPlayerGetSourceUniqueID(long dev);
long		MDPlayerGetSourceNumberFromUniqueID(long uniqueID);
long        MDPlayerAddDestinationName(const char *name);
long        MDPlayerAddSourceName(const char *name);

int			MDPlayerGetRecordedEvents(MDPlayer *inPlayer, MDEvent **outEvent, int *outEventBufSiz);
void		MDPlayerClearRecordedEvents(MDPlayer *inPlayer);

/*MDAudio *	MDPlayerGetAudioPlayer(MDPlayer *inPlayer); */

/*  These are only for internal (and debugging) use. Use MDPlayerGetRecordedEvent() to retreave recorded data.  */
int			MDPlayerPutRecordingData(MDPlayer *inPlayer, MDTimeType timeStamp, long size, const unsigned char *buf);
int			MDPlayerGetRecordingData(MDPlayer *inPlayer, MDTimeType *outTimeStamp, long *outSize, unsigned char **outBuf, long *outBufSize);

/*  Defined in MyAppController.m; will be called when any of the MIDI setup is modified  */
extern void MDPlayerNotificationCallback(void);

/*  Utility function  */
int my_usleep(unsigned long useconds);

#endif  /*  __MDPlayer_MacOSX__  */

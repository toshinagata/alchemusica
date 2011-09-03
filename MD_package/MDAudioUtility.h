/*
 *  MDAudioUtility.h
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 09/11/05.
 *  Copyright 2009-2011 Toshi Nagata. All rights reserved.
 *
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#ifndef __MDAudioUtility__
#define __MDAudioUtility__

#include <CoreAudio/CoreAudio.h>
#include <CoreAudio/CoreAudioTypes.h>
#include <Carbon/Carbon.h> // for CompareAndSwap

enum {
	kMDRingBufferError_WayBehind = -2, /* both fetch times are earlier than buffer start time */
	kMDRingBufferError_SlightlyBehind = -1, /* fetch start time is earlier than buffer start time (fetch end time OK) */
	kMDRingBufferError_OK = 0,
	kMDRingBufferError_SlightlyAhead = 1, /* fetch end time is later than buffer end time (fetch start time OK) */
	kMDRingBufferError_WayAhead = 2, /* both fetch times are later than buffer end time */
	kMDRingBufferError_TooMuch = 3, /* fetch start time is earlier than buffer start time and fetch end time is later than buffer end time */
	kMDRingBufferError_CPUOverload = 4, /* the reader is unable to get enough CPU cycles to capture a consistent snapshot of the time bounds */
	kMDRingBufferError_BufferNotLargeEnough = 5,
	kMDRingBufferError_OutOfMemory = 6,
	kMDRingBufferError_NumberBuffersMismatch = 7
};

typedef struct MDRingBuffer MDRingBuffer;
typedef SInt64 MDSampleTime;

MDRingBuffer *MDRingBufferNew(void);
int MDRingBufferAllocate(MDRingBuffer *ring, int nChannels, UInt32 bytesPerFrame, UInt32 capacityFrames);
void MDRingBufferDeallocate(MDRingBuffer *ring);
void MDRingBufferRelease(MDRingBuffer *ring);

int	MDRingBufferStore(MDRingBuffer *ring, const AudioBufferList *abl, UInt32 nFrames, MDSampleTime frameNumber);
int MDRingBufferFetch(MDRingBuffer *ring, AudioBufferList *abl, UInt32 nFrames, MDSampleTime frameNumber, bool aheadOK);
int	MDRingBufferGetTimeBounds(MDRingBuffer *ring, MDSampleTime *startTime, MDSampleTime *endTime);
int MDRingBufferFrameOffset(MDRingBuffer *ring, MDSampleTime frameNumber);

int MDRingBufferCheckTimeBounds(MDRingBuffer *ring, MDSampleTime startRead, MDSampleTime endRead, bool aheadOK);

MDSampleTime MDRingBufferStartTime(MDRingBuffer *ring);
MDSampleTime MDRingBufferEndTime(MDRingBuffer *ring);
void MDRingBufferSetTimeBounds(MDRingBuffer *ring, MDSampleTime startTime, MDSampleTime endTime);

#endif /* __MDAudioUtility__ */

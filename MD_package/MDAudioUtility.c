/*
 *  MDAudioUtility.c
 *  Alchemusica
 *
 *  Created by Toshi Nagata on 09/11/05.
 *  Copyright 2009-2025 Toshi Nagata. All rights reserved.
 *
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#include "MDAudioUtility.h"

#include <libkern/OSAtomic.h>  /*  For OSAtomicCompareAndSwap32()  */

#pragma mark ====== MDRingBuffer ======

static UInt32
sNextPowerOfTwo(UInt32 x)
{
	UInt32 n;
	for (n = 1; n != 0; n <<= 1) {
		if (n > x)
			return n;
	}
	return 0;
}

MDRingBuffer *
MDRingBufferNew(void)
{
	return (MDRingBuffer *)calloc(sizeof(MDRingBuffer), 1);
}

int
MDRingBufferAllocate(MDRingBuffer *ring, int numberBuffers, UInt32 bytesPerFrame, UInt32 capacityFrames)
{
	UInt32 allocSize;
	Byte *p;
	int i;
	UInt32 j;

	MDRingBufferDeallocate(ring);
	capacityFrames = sNextPowerOfTwo(capacityFrames);
	
	ring->numberBuffers = numberBuffers;
	ring->bytesPerFrame = bytesPerFrame;
	ring->capacityFrames = capacityFrames;
	ring->capacityFramesMask = capacityFrames - 1;
	ring->capacityBytes = bytesPerFrame * capacityFrames;
	
	// put everything in one memory allocation, first the pointers, then the deinterleaved channels
	allocSize = (ring->capacityBytes + sizeof(Byte *)) * ring->numberBuffers;
	p = (Byte *)malloc(allocSize);
	memset(p, 0, allocSize);
	ring->buffers = (Byte **)p;
	p += ring->numberBuffers * sizeof(Byte *);
	for (i = 0; i < ring->numberBuffers; ++i) {
		ring->buffers[i] = p;
		p += ring->capacityBytes;
	}
	
	for (j = 0; j < kMDRingTimeBoundsQueueSize; ++j)
	{
		ring->timeBoundsQueue[j].startTime = 0;
		ring->timeBoundsQueue[j].endTime = 0;
		ring->timeBoundsQueue[j].updateCounter = 0;
	}
	ring->timeBoundsQueuePtr = 0;
	return kMDRingBufferError_OK;
}

void
MDRingBufferDeallocate(MDRingBuffer *ring)
{
	if (ring == NULL)
		return;
	if (ring->buffers != NULL) {
		free(ring->buffers);
		ring->buffers = NULL;
	}
	ring->numberBuffers = 0;
	ring->capacityBytes = 0;
	ring->capacityFrames = 0;
}

void
MDRingBufferRelease(MDRingBuffer *ring)
{
	MDRingBufferDeallocate(ring);
	free(ring);
}

static inline void
sZeroRange(Byte **buffers, int nbuffers, int offset, int nbytes)
{
	while (--nbuffers >= 0) {
		memset(*buffers + offset, 0, nbytes);
		++buffers;
	}
}

static inline void
sStoreABL(Byte **buffers, int destOffset, const AudioBufferList *abl, int srcOffset, int nbytes)
{
	int nbuffers = abl->mNumberBuffers;
	const AudioBuffer *src = abl->mBuffers;
//    printf("Store %d bytes at [%d] from [%d]\n", nbytes, destOffset, srcOffset);
	while (--nbuffers >= 0) {
		memcpy(*buffers + destOffset, (Byte *)src->mData + srcOffset, nbytes);
		++buffers;
		++src;
	}
}

static inline void
sFetchABL(AudioBufferList *abl, int destOffset, Byte **buffers, int srcOffset, int nbytes)
{
	int nbuffers = abl->mNumberBuffers;
	AudioBuffer *dest = abl->mBuffers;
//    printf("Fetch %d bytes from [%d] to [%d]\n", nbytes, srcOffset, destOffset);
	while (--nbuffers >= 0) {
		memcpy((Byte *)dest->mData + destOffset, *buffers + srcOffset, nbytes);
		++buffers;
		++dest;
	}
}

int
MDRingBufferStore(MDRingBuffer *ring, const AudioBufferList *abl, UInt32 framesToWrite, MDSampleTime startWrite)
{
	MDSampleTime endWrite;

	if (abl->mNumberBuffers != ring->numberBuffers)
		return kMDRingBufferError_NumberBuffersMismatch;

	if (framesToWrite > ring->capacityFrames)
		return kMDRingBufferError_TooMuch;		// too big!
	
	endWrite = startWrite + framesToWrite;
	
	if (startWrite < MDRingBufferEndTime(ring)) {
		// going backwards, throw everything out
		MDRingBufferSetTimeBounds(ring, startWrite, startWrite);
	} else if (endWrite - MDRingBufferStartTime(ring) <= ring->capacityFrames) {
		// the buffer has not yet wrapped and will not need to
	} else {
		// advance the start time past the region we are about to overwrite
		MDSampleTime newStart = endWrite - ring->capacityFrames;	// one buffer of time behind where we're writing
		MDSampleTime newEnd = MDRingBufferEndTime(ring);
		if (newStart > newEnd)
			newEnd = newStart;
		MDRingBufferSetTimeBounds(ring, newStart, newEnd);
	}
	
	// write the new frames
	Byte **buffers = ring->buffers;
	int nbuffers = ring->numberBuffers;
	int offset0, offset1, nbytes;
	MDSampleTime curEnd = MDRingBufferEndTime(ring);
	
	if (startWrite > curEnd) {
		// we are skipping some samples, so zero the range we are skipping
		offset0 = MDRingBufferFrameOffset(ring, curEnd);
		offset1 = MDRingBufferFrameOffset(ring, startWrite);
		if (offset0 < offset1)
			sZeroRange(buffers, nbuffers, offset0, offset1 - offset0);
		else {
			sZeroRange(buffers, nbuffers, offset0, ring->capacityBytes - offset0);
			sZeroRange(buffers, nbuffers, 0, offset1);
		}
		offset0 = offset1;
	} else {
		offset0 = MDRingBufferFrameOffset(ring, startWrite);
	}
	
	offset1 = MDRingBufferFrameOffset(ring, endWrite);
	if (offset0 < offset1)
		sStoreABL(buffers, offset0, abl, 0, offset1 - offset0);
	else {
		nbytes = ring->capacityBytes - offset0;
		sStoreABL(buffers, offset0, abl, 0, nbytes);
		sStoreABL(buffers, 0, abl, nbytes, offset1);
	}
	
	// now update the end time
	MDRingBufferSetTimeBounds(ring, MDRingBufferStartTime(ring), endWrite);
	
	return kMDRingBufferError_OK;	// success
}

int
MDRingBufferFetch(MDRingBuffer *ring, AudioBufferList *abl, UInt32 nFrames, MDSampleTime startRead, bool aheadOK)
{
	MDSampleTime endRead = startRead + nFrames;
	int err;
	
	if (abl->mNumberBuffers != ring->numberBuffers)
		return kMDRingBufferError_NumberBuffersMismatch;

	err = MDRingBufferCheckTimeBounds(ring, startRead, endRead, aheadOK);
	if (err)
		return err;
	
	Byte **buffers = ring->buffers;
	int offset0 = MDRingBufferFrameOffset(ring, startRead);
	int offset1 = MDRingBufferFrameOffset(ring, endRead);
	int nbytes;
	
	if (offset0 < offset1) {
		sFetchABL(abl, 0, buffers, offset0, nbytes = offset1 - offset0);
	} else {
		nbytes = ring->capacityBytes - offset0;
		sFetchABL(abl, 0, buffers, offset0, nbytes);
		sFetchABL(abl, nbytes, buffers, 0, offset1);
		nbytes += offset1;
	}
	
	int nchannels = abl->mNumberBuffers;
	AudioBuffer *dest = abl->mBuffers;
	while (--nchannels >= 0)
	{
		dest->mDataByteSize = nbytes;
		dest++;
	}
	
    // now update the end time
    MDRingBufferSetTimeBounds(ring, endRead, MDRingBufferEndTime(ring));

    return kMDRingBufferError_OK;
}

int
MDRingBufferGetTimeBounds(MDRingBuffer *ring, MDSampleTime *startTime, MDSampleTime *endTime)
{
	int i;
	for (i = 0; i < 8; ++i) // fail after a few tries.
	{
		UInt32 curPtr = ring->timeBoundsQueuePtr;
		UInt32 index = curPtr & kMDRingTimeBoundsQueueMask;
		MDTimeBounds* bounds = ring->timeBoundsQueue + index;
		
		*startTime = bounds->startTime;
		*endTime = bounds->endTime;
		UInt32 newPtr = bounds->updateCounter;
		
		if (newPtr == curPtr) 
			return kMDRingBufferError_OK;
	}
	return kMDRingBufferError_CPUOverload;
}

int
MDRingBufferFrameOffset(MDRingBuffer *ring, MDSampleTime frameNumber)
{
    return (int)((frameNumber & ring->capacityFramesMask) * ring->bytesPerFrame);
}

int
MDRingBufferCheckTimeBounds(MDRingBuffer *ring, MDSampleTime startRead, MDSampleTime endRead, bool aheadOK)
{
	MDSampleTime startTime, endTime;
	
	int err = MDRingBufferGetTimeBounds(ring, &startTime, &endTime);
	if (err)
		return err;
	
	if (startRead < startTime)
	{
		if (endRead > endTime)
			return kMDRingBufferError_TooMuch;
		
		if (endRead < startTime)
			return kMDRingBufferError_WayBehind;
		else
			return kMDRingBufferError_SlightlyBehind;
	}
	
	if (endRead > endTime)	// we are going to read chunks of zeros its okay
	{
		if (aheadOK)
			return kMDRingBufferError_OK;
		else if (startRead > endTime)
			return kMDRingBufferError_WayAhead;
		else
			return kMDRingBufferError_SlightlyAhead;
	}
	
	return kMDRingBufferError_OK;	// success
}

MDSampleTime
MDRingBufferStartTime(MDRingBuffer *ring)
{
	return ring->timeBoundsQueue[ring->timeBoundsQueuePtr & kMDRingTimeBoundsQueueMask].startTime;
}

MDSampleTime
MDRingBufferEndTime(MDRingBuffer *ring)
{
	return ring->timeBoundsQueue[ring->timeBoundsQueuePtr & kMDRingTimeBoundsQueueMask].endTime;
}

void
MDRingBufferSetTimeBounds(MDRingBuffer *ring, MDSampleTime startTime, MDSampleTime endTime)
{
	UInt32 nextPtr = ring->timeBoundsQueuePtr + 1;
	UInt32 index = (nextPtr & kMDRingTimeBoundsQueueMask);
	
	ring->timeBoundsQueue[index].startTime = startTime;
	ring->timeBoundsQueue[index].endTime = endTime;
	ring->timeBoundsQueue[index].updateCounter = nextPtr;
	
	OSAtomicCompareAndSwap32(ring->timeBoundsQueuePtr, ring->timeBoundsQueuePtr + 1, (SInt32 *)(&ring->timeBoundsQueuePtr));
}

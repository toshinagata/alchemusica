/*
 *  MDTrack.c
 *
 *  Created by Toshi Nagata on Sun Jun 17 2001.

   Copyright (c) 2000-2017 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#include "MDHeaders.h"

#include <stdio.h>		/*  for sprintf() and standard I/O in MDTrackDump()  */
#include <stdlib.h>		/*  for malloc(), realloc(), and free()  */
#include <string.h>		/*  for memset() and strdup()  */
#include <limits.h>		/*  for LONG_MAX  */
#include <ctype.h>		/*  for isalpha() etc. */

#ifdef __MWERKS__
#pragma mark ====== Private definitions ======
#endif

#define kMDBlockSize		64	/*  This number of MDEvent's are allocated per MDBlock  */

typedef struct MDBlock	MDBlock;
static MDBlock *sFreeBlocks = NULL;		/*  The pool of free MDBlock's  */

struct MDBlock {
	MDBlock *		next;		/*  the next MDBlock in the linked list  */
	MDBlock *		last;		/*  the last MDBlock in the linked list  */
	int32_t			size;		/*  the number of allocated MDEvent's  */
	int32_t			num;		/*  the number of actually containing MDEvent's */
	MDEvent *		events;		/*  the array of MDEvent's  */
    MDTickType		largestTick;  /* the max value of (MDGetTick(&events[i]) + MDHasDuration(&events[i]) ? MDGetDuration(&event[i]) : 0); may be kMDNegativeTick after modification, in which case it should be recached */
};

struct MDTrack {
	int32_t			refCount;	/*  the reference count  */
	int32_t			num;		/*  the number of events  */
	int32_t			numBlocks;	/*  the number of blocks  */
	char *			name;		/*  the track name  */
	char *			devname;	/*  the device name  */
    MDTrackAttribute	attribute;  /*  the track attribute (Rec/Solo/Mute)  */
	MDBlock *		first;		/*  the first MDBlock  */
	MDBlock *		last;		/*  the last MDBlock  */
	MDTickType		duration;	/*  the track duration in ticks  */
	int32_t			nch[18];	/*  the number of channel events (16: sysex, 17: non-MIDI)  */
	int32_t			dev;		/*  the device number */
    short			channel;	/*  the MIDI channel for this track  */
                                /*  (meaningful only if the parent MDSequence is single-channel mode) */
	MDPointer *		pointer;	/*  the first MDPointer related to this track
									(MDPointer's are combined as a linked list)  */
								/*  This is a 'mutable' member, i.e. it may be modified internally
									even when a 'const MDTrack *' is passed. This behavior is
									acceptable, because this member is strictly internal. */
};

struct MDPointer {
	int32_t			refCount;	/*  the reference count  */
	MDTrack *		parent;		/*  The parent sequence. */
	MDBlock *		block;		/*  The current block. */
	int32_t			position;	/*  The current position. Can be -1, which means
								    "before the beginning". */
	int32_t			index;		/*  The current index in the current block. */
	MDPointer *		next;
	char			removed;	/*  True if the 'current' event has been removed.  */
	char			allocated;	/*  True if allocated by malloc() */
	char			autoAdjust;	/*  True if autoadjust is done after insert/delete (default is false)  */
};

struct MDTrackMerger {
    int32_t            refCount;   /*  the reference count  */
    MDPointer **    pointers;   /*  array of MDPointers  */
    int             npointers;  /*  number of MDPointers in pointers[]  */
    int             idx;        /*  the index of the 'current' track  */
};

#ifdef __MWERKS__
#pragma mark -
#pragma mark ======   MDTrack functions  ======
#endif

#ifdef __MWERKS__
#pragma mark ====== Block manipulation (private functions) ======
#endif

/* --------------------------------------
	･ MDTrackAllocateBlock
   -------------------------------------- */
static MDBlock *
MDTrackAllocateBlock(MDTrack *inTrack, MDBlock *inBlock, int32_t inSize)
{
	MDBlock *aBlock;

	if (sFreeBlocks != NULL) {
		/*  MDBlock pool から持ってくる。size と events は設定済み  */
		aBlock = sFreeBlocks;
		sFreeBlocks = sFreeBlocks->next;
	} else {
		/*  ちょっとメモリをけちったやり方。 MDBlockRecord と buffer を同時に確保している  */
		aBlock = (MDBlock *)malloc(sizeof(*aBlock) + inSize * sizeof(aBlock->events[0]));
		if (aBlock == NULL)
			/* out of memory */
			return NULL;
		aBlock->size = inSize;
		aBlock->events = (MDEvent *)(aBlock + 1);
	}

	aBlock->last = inBlock;
	if (inBlock == NULL) {
		/* top of list */
		aBlock->next = inTrack->first;
		inTrack->first = aBlock;
	} else {
		aBlock->next = inBlock->next;
		inBlock->next = aBlock;
	}
	if (aBlock->next == NULL) {
		/* bottom of list */
		inTrack->last = aBlock;
	} else {
		aBlock->next->last = aBlock;
	}

	aBlock->num = 0;
	aBlock->largestTick = kMDNegativeTick;
    
	memset(aBlock->events, 0, aBlock->size * sizeof(aBlock->events[0]));

	inTrack->numBlocks++;

	return aBlock;
}

/* --------------------------------------
	･ MDTrackDeallocateBlock
   -------------------------------------- */
static void
MDTrackDeallocateBlock(MDTrack *inTrack, MDBlock *inBlock)
{
	if (inBlock->last == NULL) {
		inTrack->first = inBlock->next;
	} else {
		inBlock->last->next = inBlock->next;
	}
	if (inBlock->next == NULL) {
		inTrack->last = inBlock->last;
	} else {
		inBlock->next->last = inBlock->last;
	}
	
	/*  MDBlock pool に戻す  */
	inBlock->next = sFreeBlocks;
	sFreeBlocks = inBlock;

	inTrack->numBlocks--;
}

/* --------------------------------------
	･ MDTrackClearBlock
   -------------------------------------- */
static void
MDTrackClearBlock(MDTrack *inTrack, MDBlock *inBlock)
{
	int32_t i;

	for (i = 0; i < inBlock->num; i++) {
		/*  パートナー、メッセージなどのポインタを処理して、メモリリーク・
		    ダングリングポインタが出ないようにする */
		MDEventClear(&(inBlock->events[i]));
	}
	inBlock->num = 0;
	MDTrackDeallocateBlock(inTrack, inBlock);	
}

/* --------------------------------------
	･ MDTrackUpdateLargestTickForBlock
 -------------------------------------- */
static void
MDTrackUpdateLargestTickForBlock(MDTrack *inTrack, MDBlock *inBlock)
{
    MDTickType tick, largestTick;
    int i;
    MDEvent *ep;
    if (inBlock->largestTick < 0) {
        /*  Recalc the largest tick and cache it  */
        largestTick = kMDNegativeTick;
        for (i = 0; i < inBlock->num; i++) {
            ep = &inBlock->events[i];
            tick = MDGetTick(ep);
            if (MDHasDuration(ep))
                tick += MDGetDuration(ep);
            if (tick > largestTick)
                largestTick = tick;
        }
        inBlock->largestTick = largestTick;
    }
}

#ifdef __MWERKS__
#pragma mark ====== Basic Insert/Delete (private functions) ======
#endif

/* --------------------------------------
	･ MDTrackInsertBlanks
   -------------------------------------- */
static int32_t
MDTrackInsertBlanks(MDTrack *inTrack, MDPointer *inPointer, int32_t count)
{
	MDBlock *block1, *block2;
	int32_t index, room, num2, tail;
	MDPointer *ptr;

	if (count <= 0)
		return count;

	block1 = inPointer->block;
	index = inPointer->index;

	if (inTrack->num == 0 || block1 == NULL) {
		room = tail = 0;
	} else {
		/*  room: the number of available space  */
		room = block1->size - block1->num;
		/*  tail: the number of events that needs to be moved (i.e. after index in block1)  */
		tail = block1->num - index;
	}
	if (room >= count) {
		/*  The current block have enough room for the required blanks  */
		MDEventMove(block1->events + index + count, block1->events + index, tail);
		block1->num += count;
        block1->largestTick = kMDNegativeTick;
	} else {
		/*  Allocate new blocks until there are enough room  */
		block2 = block1;
		while (room < count) {
			block2 = MDTrackAllocateBlock(inTrack, block2, kMDBlockSize);
			if (block2 == NULL) {
				/*  Out of memory: clean up the allocated blocks  */
				if (block1 != NULL) {
					while (block1->next != NULL && block1->next->num == 0)
						MDTrackDeallocateBlock(inTrack, block1->next);
				}
				return 0;
			}
			room += block2->size;
		}
		/*  block2: the last allocated block  */
		/*  num2: the number of events (possibly including blanks) in block2  */
		num2 = block2->size - (room - count);
		/*  Move the events after index in block1 if necessary  */
		if (tail > 0) {
			if (tail <= num2) {
				MDEventMove(block2->events + num2 - tail, block1->events + index, tail);
			} else {
				/*  block1->events[index..num-num2-1] ====> block2->last->events[size-(tail-num2)..size-1]
				    block1->events[num-num2..num-1]   ====> block2->events[0..num2-1] */
				MDEventMove(block2->events, block1->events + (block1->num - num2), num2);
				MDEventMove(block2->last->events + block2->last->size - (tail - num2), block1->events + index, tail - num2);
			}
		}
		/*  Invalidate the largestTick field  */
		if (block1 != NULL)
			block1->largestTick = kMDNegativeTick;
		/*  update the num fields of modified blocks  */
		block2->num = num2;		/*  the last allocated block  */
		/*  other blocks  */
		if (block1 == NULL)
			block1 = inTrack->first;
		while (block1 != block2) {
			block1->num = block1->size;
			block1 = block1->next;
		}
	}
	inTrack->num += count;
	
	if (inPointer->block == NULL) {
		inPointer->block = inTrack->first;
		inPointer->position = inPointer->index = 0;
	} else if (inPointer->index == inPointer->block->size) {
		/*  The pointer was at the end of track, and the last block in the track
		    had maximum number of events. In this case, a new block must have been
			allocated, so we move on to the next block and point to the first
			event in that block.  */
		inPointer->block = inPointer->block->next;
		inPointer->index = 0;
	}

	/*  Update pointers  */
	/*  (1) 0..inPointer->position-1 : no change
		(2) inPointer->position : position not changed, block/index updated as in inPointer
		(3) inPointer->position+1..inPointer->position+tail : position += count, block/index updated
		(4) inPointer->position+tail+1.. : position += count, block/index not changed  */
	num2 = inPointer->position;
	for (ptr = inTrack->pointer; ptr != NULL; ptr = ptr->next) {
		if (ptr == inPointer || !ptr->autoAdjust)
			continue;
		index = ptr->position;
		if (index > num2 + tail)
			ptr->position += count;		/*  case 4  */
		else if (index > num2) {
			/*  case 3  */
			ptr->position = inPointer->position;
			ptr->block = inPointer->block;
			ptr->index = inPointer->index;
			MDPointerSetRelativePosition(ptr, index - num2 + count);
		} else if (index == num2) {
			/*  case 2  */
			ptr->position = inPointer->position;
			ptr->block = inPointer->block;
			ptr->index = inPointer->index;
		}
	}
	
	/*  For debug  */
	for (ptr = inTrack->pointer; ptr != NULL; ptr = ptr->next) {
		if (ptr == inPointer || ptr->autoAdjust)
			MDPointerCheck(inPointer);
	}
	/*  ---------  */

	return count;
}

/* --------------------------------------
	･ MDTrackDeleteEvents
   -------------------------------------- */
static int32_t
MDTrackDeleteEvents(MDTrack *inTrack, MDPointer *inPointer, int32_t count)
{
	MDBlock *block, *block2;
	int32_t index, remain, i, n, tail;
	MDPointer *ptr;

	if (inTrack == NULL || inPointer == NULL || inPointer->parent != inTrack)
		return 0;
	if (count <= 0)
		return count;
	
	block = inPointer->block;
	index = inPointer->index;
	remain = count;
	tail = 0;
	while (remain > 0 && block != NULL) {
        block->largestTick = kMDNegativeTick;
		if (index + remain > block->num)
			n = block->num - index;
		else
			n = remain;
		for (i = 0; i < n; i++)
			MDEventClear(block->events + index + i);
		if (index + n < block->num) {
			/*  tail: the number of surviving events in the last modified block
				(used later to modify pointers)  */
			tail = block->num - (index + n);
			MDEventMove(block->events + index, block->events + index + n, tail);
		}
		block->num -= n;
		remain -= n;
		index = 0;
		block = block->next;
	}

	/*  Purge the empty blocks  */
	if (block == NULL)
		block = inTrack->last;
	while (block != NULL) {
		int endFlag = 0;
		if (block->num != 0) {
			if (block == inPointer->block)
				break;
			block = block->last;
			continue;
		}
		if (block == inPointer->block) {
			/*  inPointer is updated to point the next surviving event  */
			if (block->next != NULL) {
				inPointer->block = block->next;
				inPointer->index = 0;
			} else {
				inPointer->block = block->last;
				if (block->last == NULL)
					inPointer->index = 0;
				else inPointer->index = block->last->num;
			}
			endFlag = 1;
		}
		block2 = block->last;
		MDTrackDeallocateBlock(inTrack, block);
		block = block2;
		if (endFlag)
			break;
	}

	inPointer->removed = 1;
	inTrack->num -= count;

	/*  An ad-hoc sanity check  */
	if (inPointer->block != NULL && inPointer->block->num == inPointer->index && inPointer->block->next != NULL) {
		inPointer->block = inPointer->block->next;
		inPointer->index = 0;
	}
	
	/*  Update pointers  */
	/*  (1) 0..inPointer->position-1 : no change
		(2) inPointer->position : position not changed, block/index updated as in inPointer
		(3) inPointer->position+1..inPointer->position+count : position/block/index are made same as in inPointer
		(4) inPointer->position+count+1..inPointer->position+count+tail : position -= count, block/index updated
		(5) inPointer->position+count+tail+1 : position -= count, block/index not changed  */
	n = inPointer->position;
	for (ptr = inTrack->pointer; ptr != NULL; ptr = ptr->next) {
		if (inPointer == ptr || !ptr->autoAdjust)
			continue;
		index = ptr->position;
		if (index > n + count + tail)	/*  case 5  */
			ptr->position -= count;
		else if (index >= n) {
			ptr->position = inPointer->position;
			ptr->block = inPointer->block;
			ptr->index = inPointer->index;
			if (index > n + count) {
				/*  case 4  */
				MDPointerSetRelativePosition(ptr, index - (n + count));
			} else ptr->removed = 1;	/*  case 3 and 2  */
		} else { /* case 1 */ }
	}

	/*  Another sanity check  */
	if (inPointer->parent->num == 0 && inPointer->position >= 0) {
		inPointer->position = -1;
		inPointer->index = -1;
		inPointer->block = NULL;
	}

	/*  For debug  */
	for (ptr = inTrack->pointer; ptr != NULL; ptr = ptr->next) {
		if (ptr == inPointer || ptr->autoAdjust)
			MDPointerCheck(inPointer);
	}
	/*  ---------  */

	return count;
}

#ifdef __MWERKS__
#pragma mark ====== New/Retain/Release ======
#endif

/* --------------------------------------
	･ MDTrackNew
   -------------------------------------- */
MDTrack *
MDTrackNew(void)
{
	MDTrack *newTrack = (MDTrack *)malloc(sizeof(*newTrack));
	if (newTrack == NULL)
		return NULL;	/* out of memory */
	memset(newTrack, 0, sizeof(*newTrack));
	newTrack->refCount = 1;
    newTrack->dev = -1;
	return newTrack;
}

/* --------------------------------------
	･ MDTrackRetain
   -------------------------------------- */
void
MDTrackRetain(MDTrack *inTrack)
{
	inTrack->refCount++;
}

/* --------------------------------------
	･ MDTrackRelease
   -------------------------------------- */
void
MDTrackRelease(MDTrack *inTrack)
{
	if (--inTrack->refCount == 0) {
		if (inTrack->num != 0)
			MDTrackClear(inTrack);

		/*  Remove the MDPointer's from the linked list  */
		while (inTrack->pointer != NULL)
			MDPointerSetTrack(inTrack->pointer, NULL);

		free(inTrack);
	}
}

/* --------------------------------------
	･ MDTrackClear
   -------------------------------------- */
void
MDTrackClear(MDTrack *inTrack)
{
	MDPointer *pointer;

	while (inTrack->first != NULL) {
		MDTrackClearBlock(inTrack, inTrack->first);
	}
	inTrack->num = 0;
	
	/*  Reset the MDPointers  */
	for (pointer = inTrack->pointer; pointer != NULL; pointer = pointer->next) {
		MDPointerSetPosition(pointer, -1);
	}
}

/* --------------------------------------
	･ MDTrackNewFromTrack
   -------------------------------------- */
MDTrack *
MDTrackNewFromTrack(const MDTrack *inTrack)
{
	MDPointer *src, *dest;
	MDEvent *eventSrc, *eventDest;
	int32_t count, noteCount;
	MDTrack *newTrack;
	int i;
	
	/*  Allocate a new track  */
	newTrack = MDTrackNew();
	if (newTrack == NULL)
		return NULL;
	
	/*  Set up pointers  */
	dest = MDPointerNew(newTrack);
	src = MDPointerNew((MDTrack *)inTrack);
	if (src == NULL || dest == NULL)
		return NULL;
	MDPointerSetPosition(dest, 0);

	/*  Prepare the blank space  */
	count = MDTrackGetNumberOfEvents(inTrack);
	if (MDTrackInsertBlanks(newTrack, dest, count) < count) {
		MDTrackRelease(newTrack);
		return NULL;
	}
	
	/*  Copy the events  */
	noteCount = 0;
	while ((eventDest = MDPointerForward(dest)) != NULL && (eventSrc = MDPointerForward(src)) != NULL) {
		MDEventCopy(eventDest, eventSrc, 1);
	}
	MDPointerRelease(dest);
	MDPointerRelease(src);
		
	/*  Copy random fields  */
	for (i = 0; i < 18; i++)
		newTrack->nch[i] = inTrack->nch[i];
    newTrack->dev = inTrack->dev;
    newTrack->channel = inTrack->channel;
	newTrack->duration = inTrack->duration;
	if (inTrack->name != NULL)
		newTrack->name = strdup(inTrack->name);
	if (inTrack->devname != NULL)
		newTrack->devname = strdup(inTrack->devname);
	return newTrack;
}

/*  Exchange the contents of two MDTracks. The tracks should not have any
    "parents" such as MDSequence. Otherwise, the results are undefined.  */
void
MDTrackExchange(MDTrack *inTrack1, MDTrack *inTrack2)
{
	MDTrack tempTrack;
	MDPointer *pointer;

	/*  Exchange the contents of the MDTrack struct  */
	tempTrack = *inTrack1;
	*inTrack1 = *inTrack2;
	*inTrack2 = tempTrack;
	
	/*  Update the MDPointers  */
	for (pointer = inTrack1->pointer; pointer != NULL; pointer = pointer->next)
		pointer->parent = inTrack2;
	for (pointer = inTrack2->pointer; pointer != NULL; pointer = pointer->next)
		pointer->parent = inTrack1;
}

#ifdef __MWERKS__
#pragma mark ====== Accessor functions ======
#endif

/* --------------------------------------
	･ MDTrackGetNumberOfEvents
   -------------------------------------- */
int32_t
MDTrackGetNumberOfEvents(const MDTrack *inTrack)
{
	return inTrack->num;
}

/* --------------------------------------
	･ MDTrackGetNumberOfChannelEvents
   -------------------------------------- */
int32_t
MDTrackGetNumberOfChannelEvents(const MDTrack *inTrack, short channel)
{
	int32_t n;
	if (channel >= 0 && channel < 16)
		return inTrack->nch[channel];
	else {
		n = 0;
		for (channel = 0; channel < 16; channel++)
			n += inTrack->nch[channel];
		return n;
	}
}

/* --------------------------------------
	･ MDTrackGetNumberOfSysexEvents
   -------------------------------------- */
int32_t
MDTrackGetNumberOfSysexEvents(const MDTrack *inTrack)
{
	return inTrack->nch[16];
}

/* --------------------------------------
	･ MDTrackGetNumberOfNonMIDIEvents
   -------------------------------------- */
int32_t
MDTrackGetNumberOfNonMIDIEvents(const MDTrack *inTrack)
{
	return inTrack->nch[17];
}

/* --------------------------------------
	･ MDTrackGetDuration
   -------------------------------------- */
MDTickType
MDTrackGetDuration(const MDTrack *inTrack)
{
	return inTrack->duration;
}

/* --------------------------------------
	･ MDTrackSetDuration
   -------------------------------------- */
void
MDTrackSetDuration(MDTrack *inTrack, MDTickType inDuration)
{
	inTrack->duration = inDuration;
}

#ifdef __MWERKS__
#pragma mark ====== Insert/Delete ======
#endif

/* --------------------------------------
	･ MDTrackAppendEvents
   -------------------------------------- */
int32_t
MDTrackAppendEvents(MDTrack *inTrack, const MDEvent *inEvent, int32_t count)
{
	MDBlock *block;
	int32_t index, i, n, nn;
	if (inTrack == NULL)
		return 0;

	/*  Get the position of the last event  */
	block = inTrack->last;
	if (block == NULL) {
		block = MDTrackAllocateBlock(inTrack, NULL, kMDBlockSize);
		if (block == NULL)
			return 0;
		index = 0;
	} else index = block->num;

	n = 0;
	while (n < count) {
		if (index >= block->size) {
			block = MDTrackAllocateBlock(inTrack, block, kMDBlockSize);
			if (block == NULL)
				return n;
			index = 0;
		}
		if (count > block->size - index)
			nn = block->size - index;
		else nn = count;
		MDEventCopy(block->events + index, inEvent, nn);
		for (i = 0; i < nn; i++) {
			short ch = MDGetChannel(inEvent + i);
			if (ch >= 0 && ch < 18)
				inTrack->nch[ch]++;
		}
		block->num += nn;
        block->largestTick = kMDNegativeTick;
		index += nn;
		inEvent += nn;
		n += nn;
	}
	inTrack->num += n;
	return n;
}

/* --------------------------------------
	･ MDTrackMerge
   -------------------------------------- */
MDStatus
MDTrackMerge(MDTrack *inTrack1, const MDTrack *inTrack2, IntGroup **ioSet)
{
	MDPointer *src1;	/*  The source position in inTrack1  */
	MDPointer *src2;	/*  The source position in inTrack2  */
	MDPointer *dest;	/*  The destination position  */
	MDEvent *eventSrc1, *eventSrc2, *eventDest;
	int32_t	noteCount;	/*  The number of note-on's that have partners  */
	int32_t	destPosition;
	int32_t	i;
	MDTickType tick1, duration1, duration2;
	IntGroup *pset = NULL;
	MDStatus result = kMDNoError;
	MDBlock *block;

	if (inTrack1 == NULL || inTrack2 == NULL || inTrack2->num == 0)
		return kMDErrorNoEvents;

	src1 = MDPointerNew(inTrack1);
	dest = MDPointerNew(inTrack1);
	if (src1 == NULL || dest == NULL)
		return kMDErrorOutOfMemory;

	src2 = MDPointerNew((MDTrack *)inTrack2);
	if (src2 == NULL)
		return kMDErrorOutOfMemory;
	MDPointerSetPosition(src2, inTrack2->num - 1);

	if (ioSet != NULL) {
		pset = IntGroupNew();
		if (pset == NULL)
			return kMDErrorOutOfMemory;
	}
	eventSrc2 = MDPointerCurrent(src2);
	tick1 = MDGetTick(eventSrc2);
	
	/*  Prepare the blank space at tick = tick1 + 1 in inTrack1  */
	MDPointerJumpToTick(dest, tick1 + 1);
	if (inTrack1->num == 0)
		i = 0;
	else
		i = MDPointerGetPosition(dest);
	if (MDTrackInsertBlanks(inTrack1, dest, inTrack2->num) < inTrack2->num)
		return kMDErrorOutOfMemory;
	MDPointerSetPosition(dest, i - 1 + inTrack2->num);
	MDPointerSetPosition(src1, i - 1);

/*	i = inTrack1->num;
	MDPointerSetPosition(dest, i);
	if (MDTrackInsertBlanks(inTrack1, dest, inTrack2->num) < inTrack2->num)
		return kMDErrorOutOfMemory;
	MDPointerSetPosition(dest, inTrack1->num - 1);
	MDPointerSetPosition(src1, i - 1); */
	
	eventDest = MDPointerCurrent(dest);
	eventSrc1 = MDPointerCurrent(src1);
	noteCount = 0;
	destPosition = MDPointerGetPosition(dest);

	while (eventSrc2 != NULL) {
		/*  transfer the 'larger' event to dest  */
		unsigned char prefer_2_over_1 = 0;
	/*	MDTickType t1, t2; *//* for debug */
	/*	t1 = (eventSrc1 != NULL ? MDGetTick(eventSrc1) : kMDNegativeTick);
		t2 = MDGetTick(eventSrc2); */
		if (eventSrc1 != NULL) {
			if (MDIsTickEqual(eventSrc1, eventSrc2)) {
				if (ioSet != NULL && *ioSet != NULL) {
					/*  Consult *ioSet whether we should select eventSrc2 or not  */
					if (IntGroupLookup(*ioSet, MDPointerGetPosition(dest), NULL))
						prefer_2_over_1 = 1;
				}
			} else if (MDIsTickGreater(eventSrc2, eventSrc1)) {
				prefer_2_over_1 = 1;
			}
		} else prefer_2_over_1 = 1;
		if (prefer_2_over_1) {
			MDEventCopy(eventDest, eventSrc2, 1);
		/*	fprintf(stderr, "MDTrackMerge: MDEventCopy %ld from %ld (t1=%ld, t2=%ld)\n", MDPointerGetPosition(dest), MDPointerGetPosition(src2), t1, t2); */
			eventSrc2 = MDPointerBackward(src2);
			if (pset != NULL) {
				if (IntGroupAdd(pset, destPosition, 1) != kMDNoError) {
					result = kMDErrorOutOfMemory;
					IntGroupRelease(pset);
					pset = NULL;
				}
			}
		} else {
			MDEventMove(eventDest, eventSrc1, 1);
		/*	fprintf(stderr, "MDTrackMerge: MDEventMove %ld from %ld (t1=%ld, t2=%ld)\n", MDPointerGetPosition(dest), MDPointerGetPosition(src1), t1, t2); */
			eventSrc1 = MDPointerBackward(src1);
		}
		eventDest = MDPointerBackward(dest);
		destPosition--;
	}

	for (i = 0; i < 18; i++) {
		inTrack1->nch[i] += inTrack2->nch[i];
	}
	
    for (block = inTrack1->first; block != NULL; block = block->next)
        block->largestTick = kMDNegativeTick;

	MDPointerRelease(src2);
	MDPointerRelease(src1);
	MDPointerRelease(dest);
	
	duration1 = inTrack1->duration;
	duration2 = inTrack2->duration;
	if (duration2 > duration1)
		inTrack1->duration = duration2;

	if (ioSet != NULL)
		*ioSet = pset;
	else if (pset != NULL)
		IntGroupRelease(pset);

/*	MDTrackCheck(inTrack1);
	MDTrackCheck(inTrack2); */
	
	return result;
}

/* --------------------------------------
	･ MDTrackUnmerge
   -------------------------------------- */
static MDStatus
sMDTrackUnmergeSub(MDTrack *inTrack, MDTrack **outTrack, const IntGroup *inSet, int deleteFlag)
{
	MDPointer *src;
	MDPointer *dest;
	MDEvent *eventSrc, *eventDest;
	int32_t	ptCount;	/*  The number of points in inSet  */
	int32_t	noteCount;	/*  The number of note-on's that have partners  */
	int32_t	destPosition;
	int32_t	index, start, length;
	int i;
	MDTickType duration;
	MDTrack *newTrack;
	MDBlock *block;

	if (inTrack == NULL || inSet == NULL || (ptCount = IntGroupGetCount(inSet)) == 0)
		return kMDErrorNoEvents;
	
	/*  Allocate a destination track  */
	newTrack = MDTrackNew();
	if (newTrack == NULL)
		return kMDErrorOutOfMemory;
	
	src  = MDPointerNew(inTrack);
	dest = MDPointerNew(newTrack);
	if (src == NULL || dest == NULL)
		return kMDErrorOutOfMemory;

	/*  Prepare the blank space  */
	MDPointerSetPosition(dest, 0);
	if (MDTrackInsertBlanks(newTrack, dest, ptCount) < ptCount)
		return kMDErrorOutOfMemory;
	MDPointerSetPosition(dest, 0);
	destPosition = 0;
	eventDest = MDPointerCurrent(dest);
	duration = 0;
	noteCount = 0;

	/*  Copy the events  */
	for (index = 0; index < IntGroupGetIntervalCount(inSet); index++) {
		start = IntGroupGetStartPoint(inSet, index);
		length = IntGroupGetInterval(inSet, index);
		MDPointerSetPosition(src, start);
		eventSrc = MDPointerCurrent(src);
		while (eventDest != NULL && eventSrc != NULL && --length >= 0) {
			MDEventCopy(eventDest, eventSrc, 1);
			/*  Count the event kind  */
			if (MDIsChannelEvent(eventDest))
				newTrack->nch[MDGetChannel(eventDest)]++;
			else if (MDIsSysexEvent(eventDest))
				newTrack->nch[16]++;
			else
				newTrack->nch[17]++;

			/*  Estimated duration  */
            if (MDGetKind(eventDest) == kMDEventNote)
                duration = MDGetTick(eventDest) + MDGetDuration(eventDest) + 1;
            else
                duration = MDGetTick(eventDest) + 1;

			eventSrc = MDPointerForward(src);
			eventDest = MDPointerForward(dest);
			destPosition++;
		}
		if (eventDest == NULL)
			break;
	}
	
	/*  Check if specified number of events have been copied  */
	if (destPosition < ptCount) {
		MDTrackDeleteEvents(newTrack, dest, ptCount - destPosition);
		ptCount = destPosition;
	}

	if (deleteFlag) {
		/*  Delete the events from the source track  */
		for (index = IntGroupGetIntervalCount(inSet) - 1; index >= 0; index--) {
			start = IntGroupGetStartPoint(inSet, index);
			length = IntGroupGetInterval(inSet, index);
			if (start < inTrack->num) {
				MDPointerSetPosition(src, start);
				if (start + length > inTrack->num)
					length = inTrack->num - start;
				if (length > 0)
					MDTrackDeleteEvents(inTrack, src, length);
			}
		}
		
		for (i = 0; i < 18; i++) {
			inTrack->nch[i] -= newTrack->nch[i];
		}
		for (block = inTrack->first; block != NULL; block = block->next)
			block->largestTick = kMDNegativeTick;
	}
	
	MDPointerRelease(src);
	MDPointerRelease(dest);
	
	newTrack->duration = duration;
	
/*	MDTrackCheck(inTrack);
	MDTrackCheck(newTrack); */

	if (outTrack != NULL)
		*outTrack = newTrack;
	else if (newTrack != NULL)
		MDTrackRelease(newTrack);

	return kMDNoError;
}

MDStatus
MDTrackUnmerge(MDTrack *inTrack, MDTrack **outTrack, const IntGroup *inSet)
{
	return sMDTrackUnmergeSub(inTrack, outTrack, inSet, 1);
}

MDStatus
MDTrackExtract(MDTrack *inTrack, MDTrack **outTrack, const IntGroup *inSet)
{
	return sMDTrackUnmergeSub(inTrack, outTrack, inSet, 0);
}

/* --------------------------------------
	･ MDTrackSplitByMIDIChannel
   -------------------------------------- */
int
MDTrackSplitByMIDIChannel(MDTrack *inTrack, MDTrack **outTracks)
{
	int32_t count[16];
	int i, n, nn;
	MDPointer *pt;
	MDEvent *ep;
	IntGroup *pset;
	pt = MDPointerNew(inTrack);
	if (pt == NULL)
		return 0;
	for (i = 0; i < 16; i++) {
		count[i] = 0;
		outTracks[i] = NULL;
	}
	while ((ep = MDPointerForward(pt)) != NULL) {
		if (MDIsChannelEvent(ep))
			count[MDGetChannel(ep)]++;
	}
	for (i = n = 0; i < 16; i++) {
		if (count[i] > 0) {
			n++;
			nn = i;
		}
	}
	if (n == 0) {
		/*  No channel events  */
		outTracks[0] = inTrack;
		return 1;
	}
	if (n == 1) {
		/*  No need to split  */
		outTracks[nn] = inTrack;
		return 1;
	}
	nn = n;
	pset = IntGroupNew();
	if (pset == NULL) {
		MDPointerRelease(pt);
		return 0;
	}
	
	/*  Split by channel  */
	for (i = 15; i >= 0; i--) {
		if (count[i] == 0)
			continue;
		if (--n == 0) {
			/*  The last one  */
			outTracks[i] = inTrack;
			break;
		}
		IntGroupClear(pset);
		MDPointerSetPosition(pt, -1);
		while ((ep = MDPointerForward(pt)) != NULL) {
			if (MDIsChannelEvent(ep) && MDGetChannel(ep) == i)
				IntGroupAdd(pset, MDPointerGetPosition(pt), 1);
		}
		if (MDTrackUnmerge(inTrack, &(outTracks[i]), pset) != kMDNoError) {
			MDPointerRelease(pt);
			IntGroupRelease(pset);
			return 0;
		}
	}
	MDPointerRelease(pt);
	IntGroupRelease(pset);
	return nn;
}

/* --------------------------------------
	･ MDTrackMatchNoteOff
   -------------------------------------- */
MDStatus
MDTrackMatchNoteOff(MDTrack *inTrack, const MDEvent *noteOffEvent)
{
	MDBlock *bp;
	int index;
	unsigned char code = MDGetCode(noteOffEvent);
	int channel = MDGetChannel(noteOffEvent);
	MDTickType tick = MDGetTick(noteOffEvent);

	/*  Do not use MDPointer, but use internal block info directly (for efficiency)  */
	for (bp = inTrack->last; bp != NULL; bp = bp->last) {
		MDEvent *ep;
		for (index = bp->num - 1, ep = &(bp->events[index]); index >= 0; index--, ep--) {
			if (MDGetKind(ep) == kMDEventInternalNoteOn && MDGetCode(ep) == code && MDGetChannel(ep) == channel) {
				MDTickType duration = MDGetDuration(ep);
				if (duration == 0 || duration == tick - MDGetTick(ep)) {
					/*  Found  */
					MDSetKind(ep, kMDEventNote);
					MDSetDuration(ep, tick - MDGetTick(ep));
					MDSetNoteOffVelocity(ep, MDGetNoteOffVelocity(noteOffEvent));
					bp->largestTick = kMDNegativeTick;
					return kMDNoError;
				}
			}
		}
	}
	return kMDErrorOrphanedNoteOff;
}

/* --------------------------------------
	･ MDTrackMatchNoteOffInTrack
   -------------------------------------- */
MDStatus
MDTrackMatchNoteOffInTrack(MDTrack *inTrack, MDTrack *noteOffTrack)
{
    /*  Pair note-on with the corresponding note-off  */
    MDPointer *noteon, *noteoff;
    MDEvent *eref1, *eref2;
    MDBlock *block;
    MDTickType largestTick = kMDNegativeTick;

    noteon = MDPointerNew(inTrack);
    noteoff = MDPointerNew(noteOffTrack);
    if (noteon == NULL || noteoff == NULL)
        return kMDErrorOutOfMemory;
    while ((eref1 = MDPointerForward(noteon)) != NULL) {
        if (MDGetKind(eref1) == kMDEventInternalNoteOn) {
            MDPointerJumpToTick(noteoff, MDGetTick(eref1));
            MDPointerBackward(noteoff);
            while ((eref2 = MDPointerForward(noteoff)) != NULL) {
                if (MDGetKind(eref2) == kMDEventInternalNoteOff
                && MDGetCode(eref1) == MDGetCode(eref2)
                && MDGetChannel(eref1) == MDGetChannel(eref2)) {
                    MDTickType tick2 = MDGetTick(eref2);
                    MDSetDuration(eref1, tick2 - MDGetTick(eref1));
                    MDSetNoteOffVelocity(eref1, MDGetNoteOffVelocity(eref2));
                    MDSetKind(eref2, kMDEventNull);
					MDSetKind(eref1, kMDEventNote);
                    dprintf(2, "Paired note-event: tick %ld code %d vel %d/%d duration %ld\n", MDGetTick(eref1), MDGetCode(eref1), MDGetNoteOnVelocity(eref1), MDGetNoteOffVelocity(eref1), MDGetDuration(eref1));
                    if (tick2 > largestTick)
                        largestTick = tick2;
                    break;
                }
            }
        }
    }
    MDPointerRelease(noteon);
    MDPointerRelease(noteoff);
    for (block = inTrack->first; block != NULL; block = block->next)
        block->largestTick = kMDNegativeTick;
    if (largestTick > MDTrackGetDuration(inTrack))
        MDTrackSetDuration(inTrack, largestTick);
    return kMDNoError;
}

static int
sMDTrackEventComparator(const void *a, const void *b)
{
	MDTickType ticka, tickb;
	ticka = MDGetTick((const MDEvent *)a);
	tickb = MDGetTick((const MDEvent *)b);
	if (ticka < tickb)
		return -1;
	else if (ticka > tickb)
		return 1;
	else return 0;
}

/* --------------------------------------
	･ MDTrackChangeTick
   -------------------------------------- */
MDStatus
MDTrackChangeTick(MDTrack *inTrack, MDTickType *newTick)
{
	MDBlock *block;
/*	int index, i; */
	int32_t n, count;
	MDTickType largestTick;
/*	MDTickType oldTick, tick; */
	MDEvent *tempEvents;

#if 1
	/*  Move all events to a temporary array of MDEvent  */
	count = MDTrackGetNumberOfEvents(inTrack);
	tempEvents = (MDEvent *)malloc(sizeof(MDEvent) * count);
	if (tempEvents == NULL)
		return kMDErrorOutOfMemory;
	n = 0;
	for (block = inTrack->first; block != NULL; block = block->next) {
		MDEventMove(tempEvents + n, block->events, block->num);
		n += block->num;
	}
	
	/*  Modify tick  */
	for (n = 0; n < count; n++)
		MDSetTick(&tempEvents[n], newTick[n]);
	
	/*  Sort event index by the new tick  */
	qsort(tempEvents, count, sizeof(MDEvent), sMDTrackEventComparator);
	
	/*  Move the events back  */
	n = 0;
	for (block = inTrack->first; block != NULL; block = block->next) {
		MDEventMove(block->events, tempEvents + n, block->num);
		block->largestTick = kMDNegativeTick;
		n += block->num;
	}
	free(tempEvents);
	
#else
	/*  Pass 1: Check the new tick order first  */
	oldTick = kMDNegativeTick;
	index = 0;
	for (block = inTrack->first; block != NULL; block = block->next) {
		for (i = 0; i < block->num; i++) {
			if (newTick[index] >= 0)
				tick = newTick[index];
			else
				tick = MDGetTick(&block->events[i]);
			if (oldTick > tick)
				return kMDErrorTickDisorder;
			oldTick = tick;
			index++;
		}
	}

	/*  Pass 2: Change the tick  */
	index = 0;
	for (block = inTrack->first; block != NULL; block = block->next) {
		for (i = 0; i < block->num; i++) {
			if (newTick[index] >= 0)
				MDSetTick(&block->events[i], newTick[index]);
			index++;
		}
		block->largestTick = kMDNegativeTick;
	}
#endif

	largestTick = MDTrackGetLargestTick(inTrack);
	if (largestTick >= inTrack->duration)
		inTrack->duration = largestTick + 1;
	return kMDNoError;
}

/* --------------------------------------
	･ MDTrackOffsetTick
   -------------------------------------- */
MDStatus
MDTrackOffsetTick(MDTrack *inTrack, MDTickType offset)
{
	MDBlock *block;
	int i;
	MDTickType tick;

	for (block = inTrack->first; block != NULL; block = block->next) {
		if (block->largestTick >= 0)
			block->largestTick += offset;
		for (i = 0; i < block->num; i++) {
			MDEvent *ep = &block->events[i];
			tick = MDGetTick(ep) + offset;
			if (tick < 0) {
				tick = 0;
				block->largestTick = kMDNegativeTick;
			}
			MDSetTick(ep, tick);
		}
	}

	inTrack->duration += offset;
	tick = MDTrackGetLargestTick(inTrack);
	if (tick >= inTrack->duration)
		inTrack->duration = tick + 1;
	return kMDNoError;
}

#ifdef __MWERKS__
#pragma mark ====== Duration search ======
#endif

/* --------------------------------------
	･ MDTrackGetLargestTick
   -------------------------------------- */
MDTickType
MDTrackGetLargestTick(MDTrack *inTrack)
{
    MDTickType globalLargestTick;
    MDBlock *block;
	globalLargestTick = kMDNegativeTick;
    for (block = inTrack->first; block != NULL; block = block->next) {
        MDTrackUpdateLargestTickForBlock(inTrack, block);
        if (block->largestTick > globalLargestTick)
			globalLargestTick = block->largestTick;
	}
	return globalLargestTick;
}

/* --------------------------------------
	･ MDTrackSearchEventsWithDurationCrossingTick
   -------------------------------------- */
IntGroup *
MDTrackSearchEventsWithDurationCrossingTick(MDTrack *inTrack, MDTickType inTick)
{
    IntGroup *pset;
    int32_t position, i;
    MDTickType tick, largestTick;
    MDBlock *block;
    MDEvent *ep;
    pset = IntGroupNew();
    if (pset == NULL)
        return NULL;
    position = 0;
    for (block = inTrack->first; block != NULL; block = block->next) {
        if (block->largestTick < 0 || block->largestTick >= inTick) {
            largestTick = kMDNegativeTick;
            for (i = 0; i < block->num; i++) {
                ep = &block->events[i];
                tick = MDGetTick(ep);
                if (tick >= inTick)
                    goto exit;
                if (MDHasDuration(ep)) {
                    tick += MDGetDuration(ep);
                    if (tick >= inTick) {
                        if (IntGroupAdd(pset, position + i, 1) != kMDNoError) {
                            IntGroupRelease(pset);
                            return NULL;
                        }
                    }
                }
                if (tick > largestTick)
                    largestTick = tick;
            }
            block->largestTick = largestTick;
        }
        position += block->num;
    }
    exit:
    return pset;
}

/* --------------------------------------
	･ MDTrackSearchEventsWithSelector
   -------------------------------------- */
IntGroup *
MDTrackSearchEventsWithSelector(MDTrack *inTrack, MDEventSelector inSelector, void *inUserData)
{
    IntGroup *pset;
	MDPointer *pt;
    MDEvent *ep;
    pset = IntGroupNew();
	pt = MDPointerNew(inTrack);
    if (pset == NULL || pt == NULL)
        return NULL;
	while ((ep = MDPointerForwardWithSelector(pt, inSelector, inUserData)) != NULL) {
		if (IntGroupAdd(pset, MDPointerGetPosition(pt), 1) != kMDNoError) {
			MDPointerRelease(pt);
			IntGroupRelease(pset);
			return NULL;
		}
	}
	MDPointerRelease(pt);
	return pset;
}

#ifdef __MWERKS__
#pragma mark ====== Track/device/channel manipulations ======
#endif

/* --------------------------------------
	･ MDTrackRemapChannel
   -------------------------------------- */
void
MDTrackRemapChannel(MDTrack *inTrack, const unsigned char *newch)
{
    int32_t nnch[16];
    int32_t n;
    MDBlock *block;
	static unsigned char allzero[16] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    if (inTrack == NULL)
        return;
	if (newch == NULL)
		newch = allzero;
    for (n = 0; n < 16; n++)
        nnch[n] = 0;
    for (block = inTrack->first; block != NULL; block = block->next) {
        MDEvent *ep = block->events;
        for (n = 0; n < block->num; n++, ep++) {
            if (MDIsChannelEvent(ep)) {
                unsigned char ch;
                ch = (newch[MDGetChannel(ep) & 15]) & 15;
                MDSetChannel(ep, ch);
                nnch[ch]++;
            }
        }
    }
    for (n = 0; n < 16; n++)
        inTrack->nch[n] = nnch[n];
}

/* --------------------------------------
	･ MDTrackSetDevice
   -------------------------------------- */
void
MDTrackSetDevice(MDTrack *inTrack, int32_t dev)
{
    if (inTrack != NULL)
        inTrack->dev = dev;
}

/* --------------------------------------
	･ MDTrackGetDevice
   -------------------------------------- */
int32_t
MDTrackGetDevice(const MDTrack *inTrack)
{
    if (inTrack != NULL)
        return inTrack->dev;
    else return -1;
}

/* --------------------------------------
	･ MDTrackSetTrackChannel
   -------------------------------------- */
void
MDTrackSetTrackChannel(MDTrack *inTrack, short ch)
{
    if (inTrack != NULL)
        inTrack->channel = ch;
}

/* --------------------------------------
	･ MDTrackGetTrackChannel
   -------------------------------------- */
short
MDTrackGetTrackChannel(const MDTrack *inTrack)
{
    if (inTrack != NULL)
        return inTrack->channel;
    else return -1;
}

/* --------------------------------------
	･ MDTrackSetName
   -------------------------------------- */
MDStatus
MDTrackSetName(MDTrack *inTrack, const char *inName)
{
	char *p;
	if (inName == NULL)
		p = NULL;
	else {
		p = (char *)malloc(strlen(inName) + 1);
		if (p == NULL)
			return kMDErrorOutOfMemory;
		strcpy(p, inName);
	}
	if (inTrack->name != NULL)
		free(inTrack->name);
	inTrack->name = p;
	return kMDNoError;
}

/* --------------------------------------
	･ MDTrackGetName
   -------------------------------------- */
void
MDTrackGetName(const MDTrack *inTrack, char *outName, int32_t length)
{
	if (inTrack->name == NULL) {
		outName[0] = 0;
	} else {
			strncpy(outName, inTrack->name, length - 1);
			outName[length - 1] = 0;
	}
}

/* --------------------------------------
	･ MDTrackSetDeviceName
   -------------------------------------- */
MDStatus
MDTrackSetDeviceName(MDTrack *inTrack, const char *inName)
{
	char *p;
	if (inName == NULL)
		p = NULL;
	else {
		p = (char *)malloc(strlen(inName) + 1);
		if (p == NULL)
			return kMDErrorOutOfMemory;
		strcpy(p, inName);
	}
	if (inTrack->devname != NULL)
		free(inTrack->devname);
	inTrack->devname = p;
	return kMDNoError;
}

/* --------------------------------------
	･ MDTrackGetDeviceName
   -------------------------------------- */
void
MDTrackGetDeviceName(const MDTrack *inTrack, char *outName, int32_t length)
{
	if (inTrack->devname == NULL) {
		outName[0] = 0;
	} else {
			strncpy(outName, inTrack->devname, length - 1);
			outName[length - 1] = 0;
	}	
}

/* --------------------------------------
	･ MDTrackGuessName
   -------------------------------------- */
void
MDTrackGuessName(MDTrack *inTrack, char *outName, int32_t length)
{
	MDPointer *ptr;
	MDEvent *eref, *stopref;
	int32_t len;

	ptr = MDPointerNew(inTrack);
	
	/*  Pass 1: find the track name meta event  */
	while ((eref = MDPointerForward(ptr)) != NULL) {
		if (MDIsTextMetaEvent(eref) && MDGetCode(eref) == kMDMetaSequenceName)
			break;
		if (MDIsChannelEvent(eref) || MDIsSysexEvent(eref)) {
			stopref = eref;
			eref = NULL;
			break;	/*  not found  */
		}
	}
	
	if (eref == NULL) {
		/*  Pass 2: find the first text meta event  */
		MDPointerSetPosition(ptr, -1);
		while ((eref = MDPointerForward(ptr)) != NULL) {
			if (MDIsTextMetaEvent(eref) && MDGetCode(eref) == kMDMetaText)
				break;
			if (eref == stopref)
				break;	/*  not found  */
		}
	}
	
	if (eref != NULL && eref != stopref) {
		len = MDGetMessagePartial(eref, (unsigned char *)outName, 0, length - 1);
		outName[len] = 0;
	} else {
		outName[0] = 0;
	}
	
	MDPointerRelease(ptr);
}

/* --------------------------------------
	･ MDTrackGuessDeviceName
   -------------------------------------- */
void
MDTrackGuessDeviceName(MDTrack *inTrack, char *outName, int32_t length)
{
	MDPointer *ptr;
	MDEvent *eref, *stopref;
	char name[256];
	char c;
	char *p;
	int n, port;
	int32_t len;

	ptr = MDPointerNew(inTrack);
	
	port = -1;

	/*  Pass 1: find the device name meta event  */
	while ((eref = MDPointerForward(ptr)) != NULL) {
		if (MDIsTextMetaEvent(eref) && MDGetCode(eref) == kMDMetaDeviceName)
			break;
		if (MDIsChannelEvent(eref) || MDIsSysexEvent(eref)) {
			stopref = eref;
			eref = NULL;
			break;	/*  not found  */
		}
	}
	
	if (eref == NULL) {
		/*  Pass 2: find the instrument name meta event  */
		MDPointerSetPosition(ptr, -1);
		while ((eref = MDPointerForward(ptr)) != NULL) {
			if (MDIsTextMetaEvent(eref) && MDGetCode(eref) == kMDMetaInstrumentName)
				break;
			if (eref == stopref)
				break;	/*  not found  */
		}
	}
	
	if (eref == NULL || eref == stopref) {
		/*  Pass 3: find the port number meta event  */
		MDPointerSetPosition(ptr, -1);
		while ((eref = MDPointerForward(ptr)) != NULL) {
			if (MDGetKind(eref) == kMDEventPortNumber) {
				port = MDGetData1(eref);
				break;
			}
			if (eref == stopref)
				break;	/*  not found  */
		}
	}

	if (eref == NULL || eref == stopref) {
		/*  Pass 4: guess from the track name  */
		MDTrackGuessName(inTrack, name, 250);
		if (sscanf(name, "[%c%d]", &c, &n) == 2
		|| sscanf(name, "(%c%d)", &c, &n) == 2
		|| sscanf(name, "<%c%d>", &c, &n) == 2
		|| sscanf(name, "{%c%d}", &c, &n) == 2
		|| sscanf(name, "%c%d:", &c, &n) == 2) {
			if (isalpha(c))
				port = toupper(c) - 'A';
		} else {
			for (n = 0, p = name; name[n] != 0; n++) {
				/*  Purge non-alphanumeric characters  */
				if (isalnum(name[n]))
					*p++ = toupper(name[n]);
			}
			*p = 0;
			if (strncmp(name, "PART", 4) == 0 || strncmp(name, "PORT", 4) == 0) {
				if (isalpha(name[4]))
					port = name[4] - 'A';
				else if (isdigit(name[4]))
					port = atoi(name + 4);
			} else port = 0;
		}
	}
	
	name[0] = 0;
	if (port >= 0) {
		sprintf(name, "(Device %d)", (int)(port + 1));
	} else if (eref != NULL && eref != stopref) {
		len = MDGetMessagePartial(eref, (unsigned char *)name, 0, 255);
		name[len] = 0;
	}
	if (name[0] == 0) {
		/*  No clue  */
	/*	strcpy(name, "(Device 1)");  */
	}

	strncpy(outName, name, length - 1);
	outName[length - 1] = 0;
	
	MDPointerRelease(ptr);
}

#ifdef __MWERKS__
#pragma mark ====== Attribute manipulations ======
#endif

MDTrackAttribute
MDTrackGetAttribute(const MDTrack *inTrack)
{
    return inTrack->attribute;
}

void
MDTrackSetAttribute(MDTrack *inTrack, MDTrackAttribute inAttribute)
{
    inTrack->attribute = inAttribute;
}

#ifdef __MWERKS__
#pragma mark ====== Debugging functions ======
#endif

void
MDTrackDump(const MDTrack *inTrack)
{
	MDPointer *pt;
	MDEvent *ev;
	char buf[256];
	FILE *fp = fopen("Alchemusica.dump", "w");
	if (fp == NULL)
		fp = stdout;
	pt = MDPointerNew((MDTrack *)inTrack);
	while ((ev = MDPointerForward(pt)) != NULL) {
		fprintf(fp, "%12d ", (int)MDGetTick(ev));
		MDEventToKindString(ev, buf, sizeof buf);
		fprintf(fp, "%s ", buf);
		fprintf(fp, "%d %d %d %d ", (int)MDGetCode(ev), (int)MDGetChannel(ev), (int)MDGetData1(ev), (int)MDGetDuration(ev));
		fprintf(fp, "(@%p)\n", ev);
	}
	if (fp != NULL)
		fclose(fp);
}

int
MDTrackRecache(MDTrack *inTrack, int check)
{
	MDPointer *pt1, *pt2;
	MDEvent *ev1;
	int32_t nch[18];
	int32_t i, pos;
	MDTickType tick, lastTick;
    MDBlock *block;
	int errcnt = 0;

	pt1 = MDPointerNew((MDTrack *)inTrack);
	pt2 = MDPointerNew((MDTrack *)inTrack);
	if (pt1 == NULL || pt2 == NULL)
		return kMDErrorOutOfMemory;
    lastTick = kMDNegativeTick;
	for (i = 0; i < 18; i++)
		nch[i] = 0;
	
	pos = -1;
	while ((ev1 = MDPointerForward(pt1)) != NULL) {
		pos = MDPointerGetPosition(pt1);
		if (check && (MDGetKind(ev1) < 1 || MDGetKind(ev1) > kMDEventStop)) {
			fprintf(stderr, "#%d: invalid event kind %d\n", (int)pos, (int)MDGetKind(ev1));
			errcnt++;
		}
		tick = MDGetTick(ev1);
		if (check && tick < lastTick) {
			fprintf(stderr, "#%d: tick disorder %d (last tick = %d)\n", (int)pos, (int)tick, (int)lastTick);
			errcnt++;
		}
		lastTick = tick;
		if (MDIsChannelEvent(ev1)) {
			if (check && (unsigned)(MDGetChannel(ev1)) >= 16) {
				fprintf(stderr, "#%d: channel number (%ud) >= 16\n", (int)pos, (unsigned int)MDGetChannel(ev1));
				errcnt++;
			} else
				nch[MDGetChannel(ev1)]++;
		} else if (MDIsSysexEvent(ev1)) {
			nch[16]++;
		} else nch[17]++;
	}
	++pos;
	if (check && pos != inTrack->num) {
		fprintf(stderr, "The track->num (%d) does not match the number of events (%d)\n", pos, inTrack->num);
		errcnt++;
	}
	inTrack->num = pos;
	if (check && lastTick >= inTrack->duration) {
		fprintf(stderr, "The tick of the last event (%qd) exceeds the track duration (%qd)\n",
			(int64_t)lastTick, (int64_t)inTrack->duration);
		errcnt++;
	}
	for (i = 0; i < 18; i++) {
		if (check && nch[i] != inTrack->nch[i]) {
			fprintf(stderr, "The track->nch[%d] (%d) does not seem correct (%d)\n", (int)i, inTrack->nch[i], nch[i]);
			errcnt++;
		}
		inTrack->nch[i] = nch[i];
	}
	
	lastTick = kMDNegativeTick;
    for (block = inTrack->first; block != NULL; block = block->next) {
        tick = kMDNegativeTick;
        for (i = 0; i < block->num; i++) {
            MDTickType tick2;
            ev1 = &block->events[i];
            tick2 = MDGetTick(ev1);
            if (MDHasDuration(ev1))
                tick2 += MDGetDuration(ev1);
            if (tick2 > tick)
                tick = tick2;
        }
        if (check && (block->largestTick >= 0 && tick != block->largestTick)) {
            fprintf(stderr, "The largestTick(%d) does not match the largest tick(%d) in block %p\n", (int)block->largestTick, (int)tick, block);
			errcnt++;
        }
		block->largestTick = tick;
		if (tick > lastTick)
			lastTick = tick;
    }
	if (lastTick >= inTrack->duration) {
		if (check) {
            fprintf(stderr, "The track duration (%d) is not greater than the largest tick (%d)\n", (int)inTrack->duration, (int)lastTick);
			errcnt++;
		}
		inTrack->duration = lastTick + 1;
	}
	
	MDPointerRelease(pt1);
	MDPointerRelease(pt2);
	return errcnt;
}


#ifdef __MWERKS__
#pragma mark ====== MDPointer manipulations (private functions) ======
#endif

static void
MDTrackAttachPointer(const MDTrack *inTrack, MDPointer *inPointer)
{
	if (inTrack == NULL || inPointer == NULL)
		return;
	inPointer->next = inTrack->pointer;

	/*  pointer is a 'mutable' member, so this cast is acceptable  */
	((MDTrack *)inTrack)->pointer = inPointer;
}

static void
MDTrackDetachPointer(const MDTrack *inTrack, MDPointer *inPointer)
{
	MDPointer *currRef, *prevRef;
	if (inTrack == NULL || inPointer == NULL)
		return;
	currRef = inTrack->pointer;
	prevRef = NULL;
	while (currRef != NULL) {
		if (currRef == inPointer) {
			if (prevRef == NULL) {
				/*  pointer is a 'mutable' member, so this cast is acceptable  */
				((MDTrack *)inTrack)->pointer = currRef->next;
			} else {
				prevRef->next = currRef->next;
			}
			break;
		}
		prevRef = currRef;
		currRef = currRef->next;
	}
}

#ifdef __MWERKS__
#pragma mark -
#pragma mark ======   MDPointer functions  ======
#endif

/* --------------------------------------
	･ MDPointerNew
   -------------------------------------- */
MDPointer *
MDPointerNew(MDTrack *inTrack)
{
	MDPointer *theRef = (MDPointer *)malloc(sizeof(MDPointer));
	if (theRef == NULL)
		return NULL;	/*  out of memory  */
	
	theRef->refCount = 1;
	theRef->parent = NULL;
	theRef->next = NULL;
	theRef->block = NULL;
	theRef->position = -1;
	theRef->index = 0;
	theRef->removed = 0;
	theRef->autoAdjust = 0;
/*	theRef->allocated = 1; */
	if (inTrack != NULL)
		MDPointerSetTrack(theRef, inTrack);
	return theRef;
}

/* --------------------------------------
	･ MDPointerRetain
   -------------------------------------- */
void
MDPointerRetain(MDPointer *inPointer)
{
	inPointer->refCount++;
}

/* --------------------------------------
	･ MDPointerRelease
   -------------------------------------- */
void
MDPointerRelease(MDPointer *inPointer)
{
	if (inPointer == NULL)
		return;
	if (--inPointer->refCount == 0) {
		MDPointerSetTrack(inPointer, NULL);
		free(inPointer);
	}
}

/* --------------------------------------
	･ MDPointerCopy
   -------------------------------------- */
void
MDPointerCopy(MDPointer *inDest, const MDPointer *inSrc)
{
	if (inDest->parent == inSrc->parent) {
		inDest->block = inSrc->block;
		inDest->position = inSrc->position;
		inDest->index = inSrc->index;
		inDest->removed = inSrc->removed;
	} else {
		MDPointerSetPosition(inDest, MDPointerGetPosition(inSrc));
	}
}

/* --------------------------------------
	･ MDPointerSetTrack
   -------------------------------------- */
void
MDPointerSetTrack(MDPointer *inPointer, MDTrack *inTrack)
{
	if (inPointer->parent != inTrack) {
		if (inPointer->parent != NULL)
			MDTrackDetachPointer(inPointer->parent, inPointer);
		inPointer->parent = inTrack;
		if (inTrack != NULL)
			MDTrackAttachPointer(inTrack, inPointer);
		inPointer->position = -1;
		if (inTrack != NULL)
			inPointer->block = inTrack->first;
		else inPointer->block = NULL;
		inPointer->index = -1;
		inPointer->removed = 0;
	}
}

/* --------------------------------------
	･ MDPointerGetTrack
   -------------------------------------- */
MDTrack *
MDPointerGetTrack(const MDPointer *inPointer)
{
	return inPointer->parent;
}

/* --------------------------------------
	･ MDPointerUpdateBlock
   -------------------------------------- */
static int
MDPointerUpdateBlock(MDPointer *inPointer)
{
	int32_t num;
	int32_t position;

	num = inPointer->parent->num;
	position = inPointer->position;

	if (num == 0) {
		inPointer->block = NULL;
		inPointer->index = inPointer->position = -1;
		return 0;
	} else if (position < num / 2) {
		/*  Search the position starting from the first block  */
		inPointer->block = inPointer->parent->first;
		inPointer->index = 0;
		if (position < 0) {
			inPointer->index = inPointer->position = -1;
			return 0;
		} else {
			while (position >= inPointer->block->num) {
				position -= inPointer->block->num;
				inPointer->block = inPointer->block->next;
			}
			inPointer->index = position;
			return 1;
		}
	} else {
		/*  Search the position starting from the last block  */
		inPointer->block = inPointer->parent->last;
		inPointer->index = inPointer->block->num;
		if (position >= num) {
			inPointer->position = num;
			return 0;
		} else {
			int32_t offset = num - position;
			while (offset > inPointer->block->num) {
				offset -= inPointer->block->num;
				inPointer->block = inPointer->block->last;
			}
			inPointer->index = inPointer->block->num - offset;
			return 1;
		}
	}
}

/* --------------------------------------
	･ MDPointerSetPosition
   -------------------------------------- */
int
MDPointerSetPosition(MDPointer *inPointer, int32_t inPos)
{
	if (inPointer->parent == NULL)
		return 0;	/*  always false  */

	inPointer->position = inPos;
	inPointer->removed = 0;
	return MDPointerUpdateBlock(inPointer);
}

/* --------------------------------------
	･ MDPointerSetRelativePosition
   -------------------------------------- */
int
MDPointerSetRelativePosition(MDPointer *inPointer, int32_t inOffset)
{
	int32_t num;

	if (inPointer->parent == NULL)
		return 0;	/*  always false  */
	num = inPointer->parent->num;

	if (inOffset == 0 || num == 0)
		return (inPointer->position >= 0 && inPointer->position < num);	/*  do nothing  */

	inPointer->removed = 0;
	if (inPointer->position + inOffset < 0) {
		inPointer->block = inPointer->parent->first;
		inPointer->index = inPointer->position = -1;
		return 0;
	} else if (inPointer->position + inOffset >= num) {
		inPointer->block = inPointer->parent->last;
		inPointer->index = inPointer->block->num;
		inPointer->position = num;
		return 0;
	} else {
		inPointer->position += inOffset;
		/*  Move temporarily to the top of the current block  */
		inOffset += inPointer->index;
		inPointer->index = 0;
		if (inOffset > 0) {
			/*  Search forward  */
			while (inOffset >= inPointer->block->num) {
				inOffset -= inPointer->block->num;
				inPointer->block = inPointer->block->next;
			}
			inPointer->index = inOffset;
		} else if (inOffset < 0) {
			/*  Search backward  */
			do {
				inPointer->block = inPointer->block->last;
				inOffset += inPointer->block->num;
			} while (inOffset < 0);
			inPointer->index = inOffset;
		}
		return 1;
	}

}

/* --------------------------------------
	･ MDPointerGetPosition
   -------------------------------------- */
int32_t
MDPointerGetPosition(const MDPointer *inPointer)
{
	return inPointer->position;
}

/* --------------------------------------
	･ MDPointerSetAutoAdjust
   -------------------------------------- */
void
MDPointerSetAutoAdjust(MDPointer *inPointer, char flag)
{
	inPointer->autoAdjust = (flag != 0);
}

/* --------------------------------------
	･ MDPointerIsAutoAdjust
   -------------------------------------- */
int
MDPointerIsAutoAdjust(const MDPointer *inPointer)
{
	return inPointer->autoAdjust;
}

/* --------------------------------------
	･ MDPointerIsRemoved
   -------------------------------------- */
int
MDPointerIsRemoved(const MDPointer *inPointer)
{
	return inPointer->removed;
}

/* --------------------------------------
	･ MDPointerJumpToTick
   -------------------------------------- */
int
MDPointerJumpToTick(MDPointer *inPointer, MDTickType inTick)
{
	int32_t num;
	MDEvent event;

	if (inPointer->parent == NULL)
		return 0;	/*  always false  */
	num = inPointer->parent->num;

	/*  There are no events  */
	if (num == 0)
		return 0;
	
	inPointer->removed = 0;

	/*  Move to the top of the current block  */
	inPointer->position -= inPointer->index;
	if (inPointer->block == NULL)
		inPointer->block = inPointer->parent->first;
	inPointer->index = 0;

	/*  dummy event for comparison only  */
	MDEventInit(&event);
	MDSetTick(&event, inTick);

	/*  Look for the block whose first event >= inTick  */
	if (MDIsTickGreaterOrEqual(inPointer->block->events, &event)) {
		/*  The first event is already >= inTick  */
		/*  Search backward  */
		while (inPointer->block->last != NULL) {
			if (MDIsTickLess(inPointer->block->last->events, &event))
				break;
			inPointer->block = inPointer->block->last;
			inPointer->position -= inPointer->block->num;
		}
	} else {
		/*  Search forward  */
		do {
			inPointer->position += inPointer->block->num;
			inPointer->block = inPointer->block->next;
		} while (inPointer->block != NULL && MDIsTickLess(inPointer->block->events, &event));
	}

	if (inPointer->block != NULL &&
		(inPointer->block->last == NULL ||
		MDIsTickLess(inPointer->block->last->events + inPointer->block->last->num - 1, &event))) {
		/*  If this is the first block, or the last event in the previous block is < inEvent,
		    then the first event in this block is the goal  */
		inPointer->index = 0;
	} else {
		/*  The goal is contained in the last block  */
		if (inPointer->block == NULL) {
			inPointer->block = inPointer->parent->last;
		} else {
			/*  inPointer->block->last should not be NULL (that case is already processed in the
			    previous "if" statement)  */
			inPointer->block = inPointer->block->last;
		}
		inPointer->position -= inPointer->block->num;

		/*  Look in this block for the first event which is >= inTick  */
		/*  (If there are no such events, then the current position becomes the
		    "end of sequence")  */
		for (inPointer->index = 0; inPointer->index < inPointer->block->num; inPointer->index++) {
			if (MDIsTickGreaterOrEqual(inPointer->block->events + inPointer->index, &event))
				break;
		}
		inPointer->position += inPointer->index;
	}

	return (inPointer->position < num);
}

/* --------------------------------------
	･ MDPointerJumpToLast
   -------------------------------------- */
int
MDPointerJumpToLast(MDPointer *inPointer)
{
	if (inPointer->parent == NULL)
		return 0;
	if (inPointer->parent->last == NULL)
		return 0;
	inPointer->position = inPointer->parent->num - 1;
	inPointer->block = inPointer->parent->last;
	inPointer->index = inPointer->parent->last->num - 1;
	inPointer->removed = 0;
	return 1;
}

/* --------------------------------------
	･ MDPointerLookForEvent
   -------------------------------------- */
int
MDPointerLookForEvent(MDPointer *inPointer, const MDEvent *inEvent)
{
	int32_t savePos;
	MDBlock *saveBlock;
	MDTickType tick;

	if (inPointer->parent == NULL || inPointer->parent->num == 0 || inEvent == NULL)
		return 0;

	/*  Move to the top event in the current block  */
	inPointer->position -= inPointer->index;
	inPointer->index = 0;

	savePos = inPointer->position;
	saveBlock = inPointer->block;
	tick = MDGetTick(inEvent);

	/*  Search forward  */
	while (inPointer->block != NULL && MDGetTick(inPointer->block->events) <= tick) {
		/*  This if-statement is violating ANSI standard (i.e. it assumes arbitrary two pointers
		    can be compared).  However, this is allowed in most platforms.  */
		if (inPointer->block->events <= inEvent
			&& inEvent < inPointer->block->events + inPointer->block->num) {
				goto found;
		}
		inPointer->position += inPointer->block->num;
		inPointer->block = inPointer->block->next;
	}

	inPointer->position = savePos;
	inPointer->block = saveBlock;

	/*  Search backward  */
	while (inPointer->block != NULL && MDGetTick(inPointer->block->events) >= tick) {
		if (inPointer->block->last != NULL) {
			inPointer->block = inPointer->block->last;
			inPointer->position -= inPointer->block->num;
		} else break;
		/*  Another illegal if-statement  */
		if (inPointer->block->events <= inEvent
			&& inEvent < inPointer->block->events + inPointer->block->num) {
				goto found;
		}
	}
	
	/*  Not found  */
	inPointer->position = savePos;
	inPointer->block = saveBlock;
	return 0;
	
found:
	/*  Found  */
    inPointer->index = (int)(inEvent - inPointer->block->events);
	inPointer->position += inPointer->index;
	inPointer->removed = 0;
	return 1;
}

/* --------------------------------------
	･ MDPointerNextPos
   -------------------------------------- */
static int
MDPointerNextPos(MDPointer *inPointer)
{
	inPointer->removed = 0;
	if (inPointer->block == NULL) {
		if (inPointer->parent == NULL || inPointer->parent->num == 0)
			return 0;	/* No event: no change */
		MDPointerUpdateBlock(inPointer);
	}
	if (++(inPointer->position) == 0) {
		inPointer->block = inPointer->parent->first;
		inPointer->index = 0;
		if (inPointer->block == NULL)
			return 0;
	} else {
		if (++(inPointer->index) >= inPointer->block->num) {
			if (inPointer->block->next == NULL) {
				return 0;
			}
			inPointer->block = inPointer->block->next;
			inPointer->index = 0;
		}
	}
	return 1;
}

/* --------------------------------------
	･ MDPointerPreviousPos
   -------------------------------------- */
static int
MDPointerPreviousPos(MDPointer *inPointer)
{
	if (inPointer->position <= 0) {
		if (inPointer->position == 0) {
			inPointer->block = NULL;
			inPointer->index = -1;
			inPointer->position = -1;
		}
		return 0;
	} else {
		if ((inPointer->position)-- == inPointer->parent->num) {
			inPointer->block = inPointer->parent->last;
			inPointer->index = inPointer->block->num - 1;
		} else {
			if (--(inPointer->index) < 0) {
				inPointer->block = inPointer->block->last;	/*  This should not be NULL  */
				inPointer->index = inPointer->block->num - 1;
			}
		}
	}
	inPointer->removed = 0;
	return 1;
}

/* --------------------------------------
	･ MDPointerCurrent
   -------------------------------------- */
MDEvent *
MDPointerCurrent(const MDPointer *inPointer)
{
	if (inPointer->parent == NULL ||
	(inPointer->position < 0 || inPointer->position >= inPointer->parent->num)) {
		return NULL;
	} else {
		return inPointer->block->events + inPointer->index;
	}
}

/* --------------------------------------
	･ MDPointerForward
   -------------------------------------- */
MDEvent *
MDPointerForward(MDPointer *inPointer)
{
	if (MDPointerNextPos(inPointer)) {
		return MDPointerCurrent(inPointer);
	} else return NULL;
}

/* --------------------------------------
	･ MDPointerBackward
   -------------------------------------- */
MDEvent *
MDPointerBackward(MDPointer *inPointer)
{
	if (MDPointerPreviousPos(inPointer)) {
		return MDPointerCurrent(inPointer);
	} else return NULL;
}

/* --------------------------------------
	･ MDPointerForwardWithSelector
   -------------------------------------- */
MDEvent *
MDPointerForwardWithSelector(MDPointer *inPointer, MDEventSelector inSelector, void *inUserData)
{
	MDEvent *ep;
	int32_t position;
	while ((ep = MDPointerForward(inPointer)) != NULL) {
		position = MDPointerGetPosition(inPointer);
		if ((*inSelector)(ep, position, inUserData))
			return ep;
	}
	return NULL;
}

/* --------------------------------------
	･ MDPointerBackwardWithSelector
   -------------------------------------- */
MDEvent *
MDPointerBackwardWithSelector(MDPointer *inPointer, MDEventSelector inSelector, void *inUserData)
{
	MDEvent *ep;
	int32_t position;
	while ((ep = MDPointerBackward(inPointer)) != NULL) {
		position = MDPointerGetPosition(inPointer);
		if ((*inSelector)(ep, position, inUserData))
			return ep;
	}
	return NULL;
}

/* --------------------------------------
	･ MDPointerSetPositionWithPointSet
   -------------------------------------- */
int
MDPointerSetPositionWithPointSet(MDPointer *inPointer, IntGroup *inPointSet, int32_t offset, int *outIndex)
{
    int32_t index, position, pos, len;
    if (inPointSet == NULL)
        return 0;
    index = position = 0;
    while ((len = IntGroupGetInterval(inPointSet, index)) >= 0) {
        if (offset - position < len) {
            pos = IntGroupGetStartPoint(inPointSet, index);
            if (outIndex != NULL)
                *outIndex = index;
            return MDPointerSetPosition(inPointer, pos + (offset - position));
        }
        position += len;
        index++;
    }
    if (index > 0)
        index--;
    if (outIndex != NULL)
        *outIndex = index;
    return MDPointerSetPosition(inPointer, position);
}

/* --------------------------------------
	･ MDPointerForwardWithPointSet
   -------------------------------------- */
MDEvent *
MDPointerForwardWithPointSet(MDPointer *inPointer, IntGroup *inPointSet, int *index)
{
    int32_t pt;
	int n;
	if (index == NULL) {
		n = -1;
		index = &n;
	}
	if (!MDPointerNextPos(inPointer)) {
		/*  No more event  */
		*index = -1;
		return NULL;
	}
	if (*index >= 0) {
		if ((pt = IntGroupGetEndPoint(inPointSet, *index)) >= 0) {
			if (inPointer->position >= pt) {
				(*index)++;
				pt = IntGroupGetStartPoint(inPointSet, *index);
				if (pt < 0)
					goto end_of_pset;
				MDPointerSetRelativePosition(inPointer, pt - inPointer->position);
			}
			return MDPointerCurrent(inPointer);
		} else goto end_of_pset;  /*  This should not happen  */
	} else {
		if (!IntGroupLookup(inPointSet, inPointer->position, index)) {
			pt = IntGroupGetStartPoint(inPointSet, *index);
			if (pt < 0)
				goto end_of_pset;
			MDPointerSetRelativePosition(inPointer, pt - inPointer->position);
		}
		return MDPointerCurrent(inPointer);
	}
  end_of_pset:
	/*  No more point in pointSet  */
	MDPointerSetPosition(inPointer, inPointer->parent->num);
	return NULL;
}

/* --------------------------------------
	･ MDPointerBackwardWithPointSet
   -------------------------------------- */
MDEvent *
MDPointerBackwardWithPointSet(MDPointer *inPointer, IntGroup *inPointSet, int *index)
{
    int32_t pt;
	int n;
	if (index == NULL) {
		n = -1;
		index = &n;
	}
    if (!MDPointerPreviousPos(inPointer)) {
		*index = -1;
        return NULL;
	}
	if (*index >= 0) {
		if ((pt = IntGroupGetStartPoint(inPointSet, *index)) >= 0) {        
			if (inPointer->position < pt) {
				(*index)--;
				pt = IntGroupGetEndPoint(inPointSet, *index);
				if (pt < 0)
					goto pset_exhausted;
				MDPointerSetRelativePosition(inPointer, (pt - 1) - inPointer->position);
			}
			return MDPointerCurrent(inPointer);
		} else goto pset_exhausted;  /*  This should not happen  */
	} else {
		if (!IntGroupLookup(inPointSet, inPointer->position, index)) {
			(*index)--;
			pt = IntGroupGetEndPoint(inPointSet, *index);
			if (pt < 0)
				goto pset_exhausted;
			MDPointerSetRelativePosition(inPointer, (pt - 1) - inPointer->position);
		}
		return MDPointerCurrent(inPointer);
	}
  pset_exhausted:
	MDPointerSetPosition(inPointer, -1);
	return NULL;
}

/* --------------------------------------
	･ MDPointerInsertAnEvent
   -------------------------------------- */
MDStatus
MDPointerInsertAnEvent(MDPointer *inPointer, const MDEvent *inEvent)
{
	MDEvent *ep1, *ep2;
	MDTickType tick, ptick, tick1, tick2;
	MDStatus sts = kMDNoError;
	MDTrack *track;

	if (inPointer == NULL)
		return kMDNoError;
	track = MDPointerGetTrack(inPointer);

	/*  Check whether the pointer is in the correct position  */
	ep1 = MDPointerBackward(inPointer);
	ep2 = MDPointerForward(inPointer);
	tick1 = (ep1 == NULL ? kMDNegativeTick : MDGetTick(ep1));
	tick2 = (ep2 == NULL ? kMDMaxTick : MDGetTick(ep2));
	tick = MDGetTick(inEvent);
	if (tick1 > tick || tick > tick2)
		MDPointerJumpToTick(inPointer, tick);

	/*  Insert the event  */
	if (MDTrackInsertBlanks(inPointer->parent, inPointer, 1) == 1) {
		ep1 = MDPointerCurrent(inPointer);
		MDEventCopy(ep1, inEvent, 1);
        if (MDHasDuration(ep1))
			ptick = MDGetTick(ep1) + MDGetDuration(ep1);
		else ptick = kMDNegativeTick;
		/*  Update nch[] fields  */
		if (MDIsChannelEvent(ep1))
			track->nch[MDGetChannel(ep1) & 15]++;
		else if (MDIsSysexEvent(ep1))
			track->nch[16]++;
		else track->nch[17]++;
	} else sts = kMDErrorOutOfMemory;
	
	/*  Update track duration if necessary  */
	if (sts == kMDNoError) {
		tick1 = (ptick > tick ? ptick : tick);
		if (tick1 >= MDTrackGetDuration(track))
			MDTrackSetDuration(track, tick1 + 1);
	}
	
	return sts;
}

/* --------------------------------------
	･ MDPointerDeleteAnEvent
   -------------------------------------- */
MDStatus
MDPointerDeleteAnEvent(MDPointer *inPointer, MDEvent *outEvent)
{
	MDEvent *ep1;
	MDTrack *track;
	
	if (inPointer == NULL || (ep1 = MDPointerCurrent(inPointer)) == NULL)
		return kMDNoError;
	track = MDPointerGetTrack(inPointer);

    if (outEvent != NULL)
        MDEventCopy(outEvent, ep1, 1);
    if (MDIsChannelEvent(ep1))
        track->nch[MDGetChannel(ep1) & 15]--;
    else if (MDIsSysexEvent(ep1))
        track->nch[16]--;
    else track->nch[17]--;
    MDTrackDeleteEvents(inPointer->parent, inPointer, 1);
	return kMDNoError;
}

/* --------------------------------------
	･ MDPointerReplaceAnEvent
   -------------------------------------- */
MDStatus
MDPointerReplaceAnEvent(MDPointer *inPointer, const MDEvent *inEvent, MDEvent *outEvent)
{
    MDEvent *ep;
    MDTrack *track;
    MDTickType oldTick;
    int oldHasDuration;
    if (inPointer == NULL || (ep = MDPointerCurrent(inPointer)) == NULL)
        return kMDNoError;
    track = MDPointerGetTrack(inPointer);
    oldHasDuration = MDHasDuration(ep);
    if (outEvent != NULL)
        MDEventCopy(outEvent, ep, 1);
    if (MDIsChannelEvent(ep))
        track->nch[MDGetChannel(ep) & 15]--;
    else if (MDIsSysexEvent(ep))
        track->nch[16]--;
    else track->nch[17]--;
    oldTick = MDGetTick(ep);
    MDEventCopy(ep, inEvent, 1);
    MDSetTick(ep, oldTick);
    if (MDIsChannelEvent(ep))
        track->nch[MDGetChannel(ep) & 15]++;
    else if (MDIsSysexEvent(ep))
        track->nch[16]++;
    else track->nch[17]++;
    if (oldTick != MDGetTick(inEvent))
        return MDPointerChangeTick(inPointer, MDGetTick(inEvent), -1);
    else if (MDHasDuration(inEvent) || oldHasDuration) {
        if (MDHasDuration(inEvent)) {
            MDTickType tick1 = MDGetTick(inEvent) + MDGetDuration(inEvent);
            if (tick1 >= MDTrackGetDuration(track))
                MDTrackSetDuration(track, tick1 + 1);
        }
        inPointer->block->largestTick = kMDNegativeTick;
    }
    return kMDNoError;
}

/* --------------------------------------
	･ MDPointerChangeTick
   -------------------------------------- */
MDStatus
MDPointerChangeTick(MDPointer *inPointer, MDTickType inTick, int32_t inPosition)
{
	MDTrack *track;
	MDEvent *ep, *ep1;
	MDTickType tick, tick_last, tick_next;
	MDPointer *newPointer = NULL;
	MDStatus sts = kMDNoError;
	int oldAdjustFlag;

	if (inPointer == NULL || (ep = MDPointerCurrent(inPointer)) == NULL)
		return kMDNoError;
	
	tick = MDGetTick(ep);
	if (tick == inTick)
		return kMDNoError;

	track = MDPointerGetTrack(inPointer);

	if (inPosition < 0) {
		/*  Check whether in-place change is possible  */
		tick_last = ((ep1 = MDPointerBackward(inPointer)) != NULL ? MDGetTick(ep1) : kMDNegativeTick);
        MDPointerForward(inPointer);
		tick_next = ((ep1 = MDPointerForward(inPointer)) != NULL ? MDGetTick(ep1) : kMDMaxTick);
        MDPointerBackward(inPointer);
		if (tick_last <= inTick && inTick <= tick_next) {
			MDSetTick(ep, inTick);
            inPointer->block->largestTick = kMDNegativeTick;
            MDTrackUpdateLargestTickForBlock(track, inPointer->block);
			goto exit;
		}
	}
	
	/*  Insert/delete is required  */
	newPointer = MDPointerNew(track);
	if (newPointer == NULL)
		return kMDErrorOutOfMemory;
	if (inPosition >= 0) {
		MDPointerSetPosition(newPointer, inPosition + (inPosition >= MDPointerGetPosition(inPointer) ? 1 : 0));
		tick_last = ((ep1 = MDPointerBackward(newPointer)) != NULL ? MDGetTick(ep1) : kMDNegativeTick);
        MDPointerForward(newPointer);
		tick_next = ((ep1 = MDPointerForward(newPointer)) != NULL ? MDGetTick(ep1) : kMDMaxTick);
        MDPointerBackward(newPointer);
	}
	if (inPosition < 0 || tick_last > inTick || inTick > tick_next)
		MDPointerJumpToTick(newPointer, inTick);
	
	if (MDPointerGetPosition(newPointer) == MDPointerGetPosition(inPointer)) {
		MDSetTick(ep, inTick);
		MDPointerRelease(newPointer);
		goto exit;
	}
	
	oldAdjustFlag = MDPointerIsAutoAdjust(inPointer);
	MDPointerSetAutoAdjust(inPointer, 1);
	MDPointerSetAutoAdjust(newPointer, 1);

	/*  Insert a blank  */
	if (MDTrackInsertBlanks(track, newPointer, 1) == 1) {
		ep1 = MDPointerCurrent(newPointer);
		ep = MDPointerCurrent(inPointer);  /*  May have moved while inserting a blank  */
		MDEventMove(ep1, ep, 1);
		MDSetTick(ep1, inTick);
		/*  Delete the previous position  */
		MDTrackDeleteEvents(track, inPointer, 1);
        ep = MDPointerCurrent(newPointer);	/*  May have moved while deleting  */
	} else sts = kMDErrorOutOfMemory;
	
	MDPointerSetPosition(inPointer, MDPointerGetPosition(newPointer));
	MDPointerSetAutoAdjust(inPointer, oldAdjustFlag);
	MDPointerRelease(newPointer);

  exit:
	/*  Let the track duration greater than the last tick  */
	if (sts == kMDNoError) {
        if (MDHasDuration(ep))
            inTick += MDGetDuration(ep);
        if (inTick >= MDTrackGetDuration(track))
            MDTrackSetDuration(track, inTick + 1);
        if (inPointer->block->largestTick >= 0 && inTick > inPointer->block->largestTick)
            inPointer->block->largestTick = inTick;
    }
	return sts;
}

/* --------------------------------------
 ･ MDPointerSetDuration
 -------------------------------------- */
MDStatus
MDPointerSetDuration(MDPointer *inPointer, MDTickType inDuration)
{
	MDEvent *ep;
	if (inPointer == NULL || (ep = MDPointerCurrent(inPointer)) == NULL)
		return kMDNoError;
	
	/*  We do not check here the validity of the event type  */
	MDSetDuration(ep, inDuration);
	
	/*  Invalidate largestTick and request recalculation later  */
	inPointer->block->largestTick = kMDNegativeTick;
	
	return kMDNoError;
}

/* --------------------------------------
	･ MDPointerCheck
   -------------------------------------- */
MDStatus
MDPointerCheck(const MDPointer *inPointer)
{
	MDTrack *track;
	MDBlock *block;
	int32_t pos;
	int err = 0;
	if (inPointer == NULL)
		return kMDNoError;
	track = inPointer->parent;
	if (track == NULL) {
		fprintf(stderr, "MDPointerCheck: track is NULL\n");
		err++;
	}
	pos = inPointer->position;
	if (pos == -1) {
		if (inPointer->block != NULL) {
			fprintf(stderr, "MDPointerCheck: position is -1 but block is not NULL\n");
			err++;
		}
		if (inPointer->index != -1) {
			fprintf(stderr, "MDPointerCheck: position is -1 but index is not -1\n");
			err++;
		}
	} else {
		block = track->first;
		if (block == NULL) {
			fprintf(stderr, "MDPointerCheck: position (%d) >= 0 but track has no data\n", pos);
			err++;
		} else if (inPointer->block == NULL) {
			fprintf(stderr, "MDPointerCheck: position (%d) >= 0 but block is NULL\n", pos);
			err++;
		} else {
			while (block != NULL && pos >= block->num) {
				if (pos == block->num && block->next == NULL)
					break;
				pos -= block->num;
				block = block->next;
			}
			if (block == NULL) {
				fprintf(stderr, "MDPointerCheck: block exhausts before position (%d)\n", (int)inPointer->position);
				err++;
			} else if (block != inPointer->block || pos != inPointer->index) {
				fprintf(stderr, "MDPointerCheck: position (%d) is index %d in block %p but inPointer claims index %d in block %p\n", (int)inPointer->position, (int)(pos), block, (int)inPointer->index, inPointer->block);
				err++;
			}
		}
	}
	return (err > 0 ? kMDErrorInternalError : kMDNoError);
}

#if 0
#pragma mark ====== MDTrackMerger functions ======
#endif

/* --------------------------------------
	･ MDTrackMergerNew
 -------------------------------------- */
MDTrackMerger *
MDTrackMergerNew(void)
{
    MDTrackMerger *merger = (MDTrackMerger *)malloc(sizeof(MDTrackMerger));
    if (merger == NULL)
        return NULL;	/*  out of memory  */
    memset(merger, 0, sizeof(MDTrackMerger));
    merger->refCount = 1;
    return merger;
}

/* --------------------------------------
	･ MDTrackMergerRetain
 -------------------------------------- */
void
MDTrackMergerRetain(MDTrackMerger *inMerger)
{
    if (inMerger == NULL)
        return;
    inMerger->refCount++;
}

/* --------------------------------------
	･ MDTrackMergerRelease
 -------------------------------------- */
void
MDTrackMergerRelease(MDTrackMerger *inMerger)
{
    if (inMerger == NULL)
        return;
    if (--(inMerger->refCount) == 0) {
        /*  Deallocate  */
        int i;
        if (inMerger->npointers > 0) {
            for (i = 0; i < inMerger->npointers; i++) {
                MDPointerRelease(inMerger->pointers[i]);
            }
            free(inMerger->pointers);
        }
        free(inMerger);
    }
}

/* --------------------------------------
	･ MDTrackMergerAddTrack
 -------------------------------------- */
int
MDTrackMergerAddTrack(MDTrackMerger *inMerger, MDTrack *inTrack)
{
    MDPointer *pt;
    if (inMerger == NULL)
        return -1;
    if (inMerger->npointers % 8 == 0) {
        /*  Expand the storage  */
        MDPointer **pointers;
        if (inMerger->npointers == 0)
            pointers = (MDPointer **)malloc(sizeof(MDPointer *) * 8);
        else
            pointers = (MDPointer **)realloc(inMerger->pointers, sizeof(MDPointer *) * (inMerger->npointers + 8));
        if (pointers == NULL)
            return -1;
        memset(pointers + inMerger->npointers, 0, 8 * sizeof(MDPointer *));
        inMerger->pointers = pointers;
    }
    pt = MDPointerNew(inTrack);
    if (pt == NULL)
        return -1;
    MDPointerSetPosition(pt, 0);
    inMerger->pointers[inMerger->npointers++] = pt;
    return inMerger->npointers;
}

/* --------------------------------------
	･ MDTrackMergerRemoveTrack
 -------------------------------------- */
int
MDTrackMergerRemoveTrack(MDTrackMerger *inMerger, MDTrack *inTrack)
{
    int i;
    if (inMerger == NULL)
        return -1;
    for (i = inMerger->npointers - 1; i >= 0; i--) {
        if (MDPointerGetTrack(inMerger->pointers[i]) == inTrack) {
            /*  Remove this track  */
            MDPointerRelease(inMerger->pointers[i]);
            memmove(inMerger->pointers + i, inMerger->pointers + (i + 1), sizeof(MDPointer *) * (inMerger->npointers - (i + 1)));
            inMerger->npointers--;
            if (inMerger->npointers > 0 && inMerger->idx >= inMerger->npointers)
                inMerger->idx--;
            return inMerger->npointers;
        }
    }
    /*  Not found  */
    return -1;
}

/* --------------------------------------
	･ MDTrackMergerGetTrack
 -------------------------------------- */
MDTrack *
MDTrackMergerGetTrack(MDTrackMerger *inMerger, int num)
{
    if (inMerger == NULL || num < 0 || num >= inMerger->npointers)
        return NULL;
    return MDPointerGetTrack(inMerger->pointers[num]);
}

/* --------------------------------------
	･ MDTrackMergerJumpToTick
 -------------------------------------- */
MDEvent *
MDTrackMergerJumpToTick(MDTrackMerger *inMerger, MDTickType inTick, MDTrack **outTrack)
{
    int i, n, idx;
    MDEvent *ep;
    MDTrack *tr;
    if (inMerger == NULL)
        return NULL;
    ep = NULL;
    tr = NULL;
    n = idx = inMerger->idx;
    for (i = 0; i < inMerger->npointers; i++) {
        MDPointer *pt = inMerger->pointers[n];
        if (MDPointerJumpToTick(pt, inTick)) {
            MDEvent *ep1 = MDPointerCurrent(pt);
            if (ep1 != NULL) {
                if (ep == NULL || MDGetTick(ep) > MDGetTick(ep1)) {
                    ep = ep1;
                    tr = MDPointerGetTrack(pt);
                    idx = n;
                }
            }
        }
        if (++n == inMerger->npointers)
            n = 0;
    }
    inMerger->idx = idx;
    if (outTrack != NULL)
        *outTrack = tr;
    return ep;
}

/* --------------------------------------
	･ MDTrackMergerCurrent
 -------------------------------------- */
MDEvent *
MDTrackMergerCurrent(MDTrackMerger *inMerger, MDTrack **outTrack)
{
    int i, idx;
    MDEvent *ep;
    MDTrack *tr;
    if (inMerger == NULL)
        return NULL;
    ep = NULL;
    tr = NULL;
    idx = inMerger->idx;
    for (i = 0; i < inMerger->npointers; i++) {
        MDPointer *pt = inMerger->pointers[i];
        MDEvent *ep1 = MDPointerCurrent(pt);
        if (ep1 != NULL) {
            if (ep == NULL || MDGetTick(ep) > MDGetTick(ep1)) {
                ep = ep1;
                tr = MDPointerGetTrack(pt);
                idx = i;
            }
        }
    }
    inMerger->idx = idx;
    if (outTrack != NULL)
        *outTrack = tr;
    return ep;
}

/* --------------------------------------
	･ MDTrackMergerForward
 -------------------------------------- */
MDEvent *
MDTrackMergerForward(MDTrackMerger *inMerger, MDTrack **outTrack)
{
    if (inMerger != NULL && inMerger->npointers > 0 && inMerger->idx < inMerger->npointers) {
        MDPointerForward(inMerger->pointers[inMerger->idx]);
        return MDTrackMergerCurrent(inMerger, outTrack);
    }
    return NULL;
}

/* --------------------------------------
	･ MDTrackMergerBackward
 -------------------------------------- */
MDEvent *
MDTrackMergerBackward(MDTrackMerger *inMerger, MDTrack **outTrack)
{
    int i, idx;
    MDEvent *ep;
    MDTrack *tr;
    if (inMerger == NULL || inMerger->npointers <= 0 || inMerger->idx >= inMerger->npointers)
        return NULL;
    ep = NULL;
    tr = NULL;
    idx = inMerger->idx;
    for (i = inMerger->npointers - 1; i >= 0; i--) {
        MDPointer *pt = inMerger->pointers[i];
        MDEvent *ep1;
        if (inMerger->idx == i || MDPointerGetPosition(pt) >= MDTrackGetNumberOfEvents(MDPointerGetTrack(pt))) {
            MDPointerBackward(pt);
        }
        ep1 = MDPointerCurrent(pt);
        if (ep1 != NULL) {
            if (ep == NULL || MDGetTick(ep) < MDGetTick(ep1)) {
                ep = ep1;
                tr = MDPointerGetTrack(pt);
                idx = i;
            }
        }
    }
    inMerger->idx = idx;
    if (outTrack != NULL)
        *outTrack = tr;
    return ep;
}

/*
   MDSequence.c
   Created by Toshi Nagata, 2000.11.24.

   Copyright (c) 2000-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#include "MDHeaders.h"

#include <stdio.h>		/*  for sprintf()  */
#include <stdlib.h>		/*  for malloc(), realloc(), and free()  */
#include <string.h>		/*  for memset()  */
#include <limits.h>		/*  for LONG_MAX  */
#include <pthread.h>    /*  for mutex  */

#ifdef __MWERKS__
#pragma mark ====== Private definitions ======
#endif

struct MDSequence {
	int32_t			refCount;	/*  the reference count  */
	int32_t			timebase;	/*  the timebase  */
	int32_t			num;		/*  the number of tracks (including the conductor track)  */
    unsigned char	single;		/*  non-zero if single channel mode  */
	MDArray *		tracks;		/*  the array of tracks (the 0-th is the conductor track)  */
	MDCalibrator *	calib;		/*  the first MDCalibrator related to this sequence  */
/*	MDMerger *		merger;		*//*  the first MDMerger related to this sequence  */
	pthread_mutex_t *mutex;		/*  the mutex for lock/unlock  */
};

#if 0
/*  A private struct for MDMerger  */
typedef struct MDMergerInfo {
	MDTrack *		track;
	MDPointer *		ptr;
	MDEvent *		eptr;
	MDTickType		tick;
	MDTickType		lastTick;
} MDMergerInfo;

struct MDMerger {
	int32_t			refCount;
	MDSequence *	sequence;
	MDMerger *		next;
	int32_t			currentTrack;
	MDEvent *		eptr;
	MDTickType		tick;
	MDArray			*info;			//  MDMergerInfo の array
};
#endif

#ifdef __MWERKS__
#pragma mark -
#pragma mark ======   MDSequence functions  ======
#endif

#ifdef __MWERKS__
#pragma mark ====== New/Retain/Release ======
#endif

/* --------------------------------------
	･ MDSequenceNew
   -------------------------------------- */
MDSequence *
MDSequenceNew(void)
{
	MDSequence *newSequence = (MDSequence *)malloc(sizeof(*newSequence));
	if (newSequence == NULL)
		return NULL;	/* out of memory */
    memset(newSequence, 0, sizeof(MDSequence));
	newSequence->num = 0;
	newSequence->refCount = 1;
	newSequence->timebase = 480;
	newSequence->tracks = MDArrayNew(sizeof(MDTrack *));
	if (newSequence->tracks == NULL) {
		free(newSequence);
		return NULL;
	}
	newSequence->calib = NULL;
	return newSequence;
}

/* --------------------------------------
	･ MDSequenceRetain
   -------------------------------------- */
void
MDSequenceRetain(MDSequence *inSequence)
{
	inSequence->refCount++;
}

/* --------------------------------------
	･ MDSequenceRelease
   -------------------------------------- */
void
MDSequenceRelease(MDSequence *inSequence)
{
	if (--inSequence->refCount == 0) {

		MDSequenceClear(inSequence);
		MDArrayRelease(inSequence->tracks);
		
		/*  Remove the MDCache's from the linked list  */
	/*  while (inSequence->calib != NULL)
			MDCacheSetSequence(inSequence->cache, NULL);
	*/	
		free(inSequence);
	}
}

/* --------------------------------------
	･ MDSequenceClear
   -------------------------------------- */
void
MDSequenceClear(MDSequence *inSequence)
{
	MDTrack *track;
	int i;
	if (inSequence->num != 0) {
		for (i = 0; i < inSequence->num; i++) {
			track = MDSequenceGetTrack(inSequence, i);
			if (track != NULL) {
				MDTrackClear(track);
				MDTrackRelease(track);
			}
		}
		MDArrayEmpty(inSequence->tracks);
		inSequence->num = 0;
	}
}

#ifdef __MWERKS__
#pragma mark ====== MDCalibrator manipulations ======
#endif

static void
MDSequenceRemoveCalibratorForTrack(MDSequence *inSequence, MDTrack *inTrack)
{
    MDCalibrator *calib;
    int index;
    MDTrack *track;
    if (inSequence == NULL || inTrack == NULL)
        return;
    for (calib = inSequence->calib; calib != NULL; calib = MDCalibratorNextInList(calib)) {
        index = 0;
        while (MDCalibratorGetInfo(calib, index, &track, NULL, NULL) == kMDNoError) {
            if (track == inTrack) {
                MDCalibratorRemoveAtIndex(calib, index);
            } else index++;
        }
    }
}

void
MDSequenceAttachCalibrator(MDSequence *inSequence, MDCalibrator *inCalib)
{
	if (inSequence == NULL || inCalib == NULL)
		return;
	MDCalibratorSetNextInList(inCalib, inSequence->calib);
	inSequence->calib = inCalib;
}

void
MDSequenceDetachCalibrator(MDSequence *inSequence, MDCalibrator *inCalib)
{
	MDCalibrator *curr, *prev, *next;
	if (inSequence == NULL || inCalib == NULL)
		return;
	curr = inSequence->calib;
	prev = NULL;
	next = MDCalibratorNextInList(inCalib);
	while (curr != NULL) {
		if (curr == inCalib) {
			if (prev == NULL) {
				inSequence->calib = next;
			} else {
				MDCalibratorSetNextInList(prev, next);
			}
			break;
		}
		prev = curr;
		curr = MDCalibratorNextInList(curr);
	}
}

#ifdef __MWERKS__
#pragma mark ====== Accessor functions ======
#endif

/* --------------------------------------
	･ MDSequenceSetTimebase
   -------------------------------------- */
void
MDSequenceSetTimebase(MDSequence *inSequence, int32_t inTimebase)
{
	inSequence->timebase = inTimebase;
}

/* --------------------------------------
	･ MDSequenceGetTimebase
   -------------------------------------- */
int32_t
MDSequenceGetTimebase(const MDSequence *inSequence)
{
	return inSequence->timebase;
}

/* --------------------------------------
	･ MDSequenceGetNumberOfTracks
   -------------------------------------- */
int32_t
MDSequenceGetNumberOfTracks(const MDSequence *inSequence)
{
	return inSequence->num;
}

/* --------------------------------------
	･ MDSequenceGetDuration
   -------------------------------------- */
MDTickType
MDSequenceGetDuration(const MDSequence *inSequence)
{
	MDTrack *track;
	int32_t n;
	MDTickType duration, maxDuration;
	maxDuration = 0;
	for (n = inSequence->num - 1; n >= 0; n--) {
		track = MDSequenceGetTrack(inSequence, n);
		if (track != NULL) {
			duration = MDTrackGetDuration(track);
			if (duration > maxDuration)
				maxDuration = duration;
		}
	}
	return maxDuration;
}

/* --------------------------------------
	･ MDSequenceGetTrack
   -------------------------------------- */
MDTrack *
MDSequenceGetTrack(const MDSequence *inSequence, int32_t index)
{
	MDTrack *track;
	if (MDArrayFetch(inSequence->tracks, index, 1, &track) == 1)
		return track;
	else return NULL;
}

#ifdef __MWERKS__
#pragma mark ====== MDTrack attribute manipulations ======
#endif

void
MDSequenceUpdateMuteBySoloFlag(MDSequence *inSequence)
{
	MDTrack *track;
	int32_t n, solo;
    MDTrackAttribute attr;
    solo = 0;
	for (n = inSequence->num - 1; n >= 0; n--) {
		track = MDSequenceGetTrack(inSequence, n);
		if (track != NULL) {
            attr = MDTrackGetAttribute(track);
            if (attr & kMDTrackAttributeSolo)
                solo++;
        }
	}
    for (n = inSequence->num - 1; n >= 0; n--) {
		track = MDSequenceGetTrack(inSequence, n);
		if (track != NULL) {
            attr = MDTrackGetAttribute(track);
            if (solo > 0)
                attr = (attr & ~kMDTrackAttributeMuteBySolo) |
                    ((attr & kMDTrackAttributeSolo) ? 0 : kMDTrackAttributeMuteBySolo);
            else
                attr = (attr & ~kMDTrackAttributeMuteBySolo);
            MDTrackSetAttribute(track, attr);
        }
	}
}

/* --------------------------------------
	･ MDSequenceSetRecordFlagOnTrack
   -------------------------------------- */
int
MDSequenceSetRecordFlagOnTrack(MDSequence *inSequence, int32_t index, int flag)
{
    MDTrack *track;
    int32_t n;
    MDTrackAttribute attr, newAttr;
    if (index < 0 || index >= inSequence->num || (track = MDSequenceGetTrack(inSequence, index)) == NULL)
        return 0;
    attr = MDTrackGetAttribute(track);
    if (flag < 0)
        attr ^= kMDTrackAttributeRecord;
    else {
        newAttr = (attr & ~kMDTrackAttributeRecord) | (flag ? kMDTrackAttributeRecord : 0);
        if (newAttr == attr)
            return 0;
        attr = newAttr;
    }
    MDTrackSetAttribute(track, attr);
    if (attr & kMDTrackAttributeRecord) {
        for (n = inSequence->num - 1; n >= 0; n--) {
            if (n == index || (track = MDSequenceGetTrack(inSequence, n)) == NULL)
                continue;
            attr = MDTrackGetAttribute(track);
            attr &= ~kMDTrackAttributeRecord;
            MDTrackSetAttribute(track, attr);
        }
    }
    return 1;
}

/* --------------------------------------
	･ MDSequenceSetSoloFlagOnTrack
   -------------------------------------- */
int
MDSequenceSetSoloFlagOnTrack(MDSequence *inSequence, int32_t index, int flag)
{
    MDTrack *track;
    MDTrackAttribute attr, newAttr;
    if (index < 0 || index >= inSequence->num || (track = MDSequenceGetTrack(inSequence, index)) == NULL)
        return 0;
    attr = MDTrackGetAttribute(track);
    if (flag < 0)
        attr ^= kMDTrackAttributeSolo;
    else {
        newAttr = (attr & ~kMDTrackAttributeSolo) | (flag ? kMDTrackAttributeSolo : 0);
        if (attr == newAttr)
            return 0;
        attr = newAttr;
    }
    MDTrackSetAttribute(track, attr);
    MDSequenceUpdateMuteBySoloFlag(inSequence);
    return 1;
}

/* --------------------------------------
	･ MDSequenceSetMuteFlagOnTrack
   -------------------------------------- */
int
MDSequenceSetMuteFlagOnTrack(MDSequence *inSequence, int32_t index, int flag)
{
    MDTrack *track;
    MDTrackAttribute attr, newAttr;
    if (index < 0 || index >= inSequence->num || (track = MDSequenceGetTrack(inSequence, index)) == NULL)
        return 0;
    attr = MDTrackGetAttribute(track);
    if (flag < 0)
        attr ^= kMDTrackAttributeMute;
    else {
        newAttr = (attr & ~kMDTrackAttributeMute) | (flag ? kMDTrackAttributeMute : 0);
        if (attr == newAttr)
            return 0;
        attr = newAttr;
    }
    MDTrackSetAttribute(track, attr);
    return 1;
}

/* --------------------------------------
	･ MDSequenceGetIndexOfRecordingTrack
   -------------------------------------- */
int32_t
MDSequenceGetIndexOfRecordingTrack(MDSequence *inSequence)
{
    int32_t index;
    for (index = 0; index < inSequence->num; index++) {
        MDTrack *track = MDSequenceGetTrack(inSequence, index);
        if (track != NULL && (MDTrackGetAttribute(track) & kMDTrackAttributeRecord) != 0)
            return index;
    }
    return -1;
}

#ifdef __MWERKS__
#pragma mark ====== MDTrack Insert/Delete ======
#endif

/* --------------------------------------
	･ MDSequenceInsertTrack
   -------------------------------------- */
int32_t
MDSequenceInsertTrack(MDSequence *inSequence, int32_t index, MDTrack *inTrack)
{
	if (index < -1)
		index = 0;
	else if (index == -1 || index > inSequence->num)
		index = inSequence->num;
	if (MDArrayInsert(inSequence->tracks, index, 1, &inTrack) == kMDNoError) {
		inSequence->num++;
		MDTrackRetain(inTrack);

        /*  Check track attributes  */
        if (MDTrackGetAttribute(inTrack) & kMDTrackAttributeRecord)
            MDSequenceSetRecordFlagOnTrack(inSequence, index, 1);
        MDSequenceUpdateMuteBySoloFlag(inSequence);

		return index;
	} else return -1;
}

/* --------------------------------------
	･ MDSequenceDeleteTrack
   -------------------------------------- */
int32_t
MDSequenceDeleteTrack(MDSequence *inSequence, int32_t index)
{
	MDTrack *track;
	if (index < 0 || index >= inSequence->num)
		return -1;
	track = MDSequenceGetTrack(inSequence, index);
    MDSequenceRemoveCalibratorForTrack(inSequence, track);
	if (MDArrayDelete(inSequence->tracks, index, 1) == kMDNoError) {
		inSequence->num--;
		if (track != NULL)
			MDTrackRelease(track);
        MDSequenceUpdateMuteBySoloFlag(inSequence);
		return index;
	} else return -1;
}

/* --------------------------------------
	･ MDSequenceReplaceTrack
   -------------------------------------- */
int32_t
MDSequenceReplaceTrack(MDSequence *inSequence, int32_t index, MDTrack *inTrack)
{
    int32_t n;
	if (index < 0 || index >= inSequence->num)
		return -1;
    n = MDSequenceDeleteTrack(inSequence, index);
    if (n >= 0)
        return MDSequenceInsertTrack(inSequence, index, inTrack);
    else return n;
}

/* --------------------------------------
	･ MDSequenceResetCalibrators
   -------------------------------------- */
void
MDSequenceResetCalibrators(MDSequence *inSequence)
{
	MDCalibrator *calib;
	for (calib = inSequence->calib; calib != NULL; calib = MDCalibratorNextInList(calib)) {
		MDCalibratorReset(calib);
	}
}

#ifdef __MWERKS__
#pragma mark ====== Single/Multi channel mode ======
#endif

/* --------------------------------------
	･ MDSequenceSingleChannelMode
   -------------------------------------- */
MDStatus
MDSequenceSingleChannelMode(MDSequence *inSequence, int separate)
{
    int32_t n;
    int32_t nch[16];
    MDStatus sts = kMDNoError;

    if (inSequence == NULL)
        return kMDNoError;

    /*  Pass 1: Separate multi-channel tracks  */
	if (separate) {
		for (n = inSequence->num - 1; n >= 0; n--) {
			MDTrack *track, *ntrack[16];
			MDPointer *pt;
			IntGroup *pset;
			int nnch, i;
			track = MDSequenceGetTrack(inSequence, n);
			nnch = 0;
			for (i = 0; i < 16; i++) {
				nch[i] = MDTrackGetNumberOfChannelEvents(track, i);
				if (nch[i] > 0)
					nnch++;
			}
			if (nnch <= 1)
				continue;
			memset(ntrack, 0, sizeof(ntrack));
			ntrack[0] = MDTrackNewFromTrack(track);  /*  Duplicate  */
			if (ntrack[0] == NULL)
				return kMDErrorOutOfMemory;
			pt = MDPointerNew(ntrack[0]);
			pset = IntGroupNew();
			if (pt == NULL || pset == NULL)
				return kMDErrorOutOfMemory;
			for (i = 15; i >= 1; i--) {
				MDEvent *ep;
				if (nch[i] == 0)
					continue;
				MDPointerSetPosition(pt, -1);
				IntGroupClear(pset);
				while ((ep = MDPointerForward(pt)) != NULL) {
					if (MDIsChannelEvent(ep) && MDGetChannel(ep) == i) {
						sts = IntGroupAdd(pset, MDPointerGetPosition(pt), 1);
						if (sts != kMDNoError)
							break;
					}
				}
				if (sts == kMDNoError)
					sts = MDTrackUnmerge(ntrack[0], &ntrack[i], pset);
				if (sts == kMDNoError) {
					nnch--;
					if (nnch == 1)
						break;
				} else break;
			}
			IntGroupRelease(pset);
			MDPointerRelease(pt);
			if (sts == kMDNoError) {
				for (i = 15; i >= 0; i--) {
					if (ntrack[i] == NULL)
						continue;
					if (MDSequenceInsertTrack(inSequence, n + 1, ntrack[i]) < 0) {
						sts = kMDErrorOutOfMemory;
						break;
					} else {
						ntrack[i] = NULL;
					}
				}
			}
			if (sts == kMDNoError) {
				MDSequenceDeleteTrack(inSequence, n);
			} else {
				/*  Dispose all temporary objects and returns error  */
				for (i = 0; i < 16; i++) {
					if (ntrack[i] != NULL)
						MDTrackRelease(ntrack[i]);
				}
				return sts;
			}
		}
	}
    
    /*  Pass 2: Remap all events to MIDI channel 0, and set the track channels  */
    for (n = inSequence->num - 1; n >= 0; n--) {
        MDTrack *track;
        int i, nnch;
        unsigned char newch[16];
        track = MDSequenceGetTrack(inSequence, n);
        if (track == NULL)
            continue;
        memset(newch, 0, 16);
        nnch = 0;
        /*  Set the track channel  */
        for (i = 0; i < 16; i++) {
            if (MDTrackGetNumberOfChannelEvents(track, i) > 0) {
                MDTrackSetTrackChannel(track, i);
                if (separate && nnch++ > 0)
                    fprintf(stderr, "Warning: Internal inconsistency in function MDSequenceSingleChannelMode, file %s, line %d\n", __FILE__, __LINE__);
            }
        }
        MDTrackRemapChannel(track, newch);
    }
    
    inSequence->single = 1;
    
    return kMDNoError;
}

/* --------------------------------------
	･ MDSequenceMultiChannelMode
   -------------------------------------- */
MDStatus
MDSequenceMultiChannelMode(MDSequence *inSequence)
{
    int32_t n;
    MDTrack *track;
    unsigned char newch[16];
    if (inSequence == NULL)
        return kMDNoError;
    memset(newch, 0, 16);
    for (n = 0; n < inSequence->num; n++) {
        track = MDSequenceGetTrack(inSequence, n);
        if (track == NULL)
            continue;
        if (MDTrackGetNumberOfChannelEvents(track, -1) == 0)
            continue;
        newch[0] = MDTrackGetTrackChannel(track) & 15;
        MDTrackRemapChannel(track, newch);
        MDTrackSetTrackChannel(track, 0);
    }
    inSequence->single = 0;
    return kMDNoError;
}

/* --------------------------------------
	･ MDSequenceIsSingleChannelMode
   -------------------------------------- */
int
MDSequenceIsSingleChannelMode(const MDSequence *inSequence)
{
    if (inSequence != NULL)
        return (inSequence->single != 0);
    else return 0;
}

#pragma mark ======   MDSequence Lock/Unlock  ======

MDStatus
MDSequenceCreateMutex(MDSequence *inSequence)
{
	int n;
	if (inSequence == NULL)
		return kMDErrorInternalError;
	else if (inSequence->mutex != NULL)
		return kMDErrorOnSequenceMutex;
	else {
		inSequence->mutex = (pthread_mutex_t *)calloc(sizeof(pthread_mutex_t), 1);
		if (inSequence->mutex == NULL)
			return kMDErrorOutOfMemory;
		n = pthread_mutex_init(inSequence->mutex, NULL);
		if (n != 0)
			return kMDErrorOnSequenceMutex;
	}
	return kMDNoError;
}

MDStatus
MDSequenceDisposeMutex(MDSequence *inSequence)
{
	int n;
	if (inSequence == NULL || inSequence->mutex == NULL)
		return kMDErrorInternalError;
	n = pthread_mutex_destroy(inSequence->mutex);
	free(inSequence->mutex);
	inSequence->mutex = NULL;
	if (n != 0)
		return kMDErrorOnSequenceMutex;
	else return kMDNoError;
}

void
MDSequenceLock(MDSequence *inSequence)
{
	int n;
	if (inSequence == NULL || inSequence->mutex == NULL)
		return;
	n = pthread_mutex_lock(inSequence->mutex);
}

void
MDSequenceUnlock(MDSequence *inSequence)
{
	int n;
	if (inSequence == NULL || inSequence->mutex == NULL)
		return;
	n = pthread_mutex_unlock(inSequence->mutex);
}

int
MDSequenceTryLock(MDSequence *inSequence)
{
	int n;
	if (inSequence == NULL || inSequence->mutex == NULL)
		return 0;
	n = pthread_mutex_trylock(inSequence->mutex);
	if (n == 0)
		return 0;
	else if (n == EBUSY)
		return 1;
	else return -1;
}

#ifdef __MWERKS__
#pragma mark ====== MDMerger manipulations ======
#endif

#if 0
static void
MDSequenceAttachMerger(const MDSequence *inSequence, MDMerger *inMerger)
{
    if (inSequence == NULL || inMerger == NULL)
        return;
    inMerger->next = inSequence->merger;
    
    /*  merger is a 'mutable' member, so this cast is acceptable  */
    ((MDSequence *)inSequence)->merger = inMerger;
}

static void
MDSequenceDetachMerger(const MDSequence *inSequence, MDMerger *inMerger)
{
    MDMerger *currRef, *prevRef;
    if (inSequence == NULL || inMerger == NULL)
        return;
    currRef = inSequence->merger;
    prevRef = NULL;
    while (currRef != NULL) {
        if (currRef == inMerger) {
            if (prevRef == NULL) {
                /*  merger is a 'mutable' member, so this cast is acceptable  */
                ((MDSequence *)inSequence)->merger = currRef->next;
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
#pragma mark ======   MDMerger functions   ======
#endif

/* --------------------------------------
	･ MDMergerNew
   -------------------------------------- */
MDMerger *
MDMergerNew(MDSequence *inSequence)
{
	MDMerger *newMerger = (MDMerger *)malloc(sizeof(*newMerger));
	if (newMerger == NULL)
		return NULL;	/* out of memory */
	memset(newMerger, 0, sizeof(*newMerger));
	newMerger->refCount = 1;
	newMerger->sequence = NULL;
	newMerger->next = NULL;
	newMerger->currentTrack = 0;
	newMerger->eptr = NULL;
	newMerger->tick = -1;
	newMerger->info = NULL;
	if (inSequence != NULL)
		MDMergerSetSequence(newMerger, inSequence);
	return newMerger;
}

/* --------------------------------------
	･ MDMergerRetain
   -------------------------------------- */
void
MDMergerRetain(MDMerger *inMerger)
{
	inMerger->refCount++;
}

/* --------------------------------------
	･ MDMergerRelease
   -------------------------------------- */
void
MDMergerRelease(MDMerger *inMerger)
{
	int32_t i, num;
	if (--inMerger->refCount == 0) {
		if (inMerger->info != NULL) {
			num = MDArrayCount(inMerger->info);
			for (i = 0; i < num; i++) {
				MDMergerInfo info;
				if (MDArrayFetch(inMerger->info, i, 1, &info) == 1) {
					if (info.ptr != NULL)
						MDPointerRelease(info.ptr);
					if (info.track != NULL)
						MDTrackRelease(info.track);
				}
			}
			MDArrayRelease(inMerger->info);
		}
		if (inMerger->sequence != NULL) {
			MDSequenceDetachMerger(inMerger->sequence, inMerger);
			MDSequenceRelease(inMerger->sequence);
		}
		free(inMerger);
	}
}

/* --------------------------------------
	･ MDMergerDuplicate
   -------------------------------------- */
MDMerger *
MDMergerDuplicate(const MDMerger *inSrc)
{
	MDMergerInfo anInfo, aSrcInfo;
	int32_t n;
	MDMerger *dest = MDMergerNew(NULL);
	if (dest != NULL) {
		dest->info = MDArrayNew(sizeof(MDMergerInfo));
		if (dest->info == NULL) {
			MDMergerRelease(dest);
			return NULL;
		}
		for (n = MDArrayCount(inSrc->info) - 1; n >= 0; n--) {
			if (MDArrayFetch(inSrc->info, n, 1, &aSrcInfo) == 1) {
				anInfo.track = aSrcInfo.track;
				MDTrackRetain(anInfo.track);
				anInfo.ptr = MDPointerNew(anInfo.track);
				MDPointerSetAutoAdjust(anInfo.ptr, 1);
				MDPointerCopy(anInfo.ptr, aSrcInfo.ptr);
				anInfo.eptr = aSrcInfo.eptr;
				anInfo.tick = aSrcInfo.tick;
				anInfo.lastTick = aSrcInfo.lastTick;
			} else {
				anInfo.track = NULL;
				anInfo.ptr = NULL;
				anInfo.eptr = NULL;
				anInfo.tick = kMDMaxTick;
				anInfo.lastTick = kMDNegativeTick;
			}
			MDArrayReplace(dest->info, n, 1, &anInfo);
		}
		dest->currentTrack = inSrc->currentTrack;
		dest->eptr = inSrc->eptr;
		dest->tick = inSrc->tick;
		dest->sequence = inSrc->sequence;
		if (dest->sequence != NULL) {
			MDSequenceRetain(dest->sequence);
			MDSequenceAttachMerger(dest->sequence, dest);
		}
	}
	return dest;
}

/* --------------------------------------
	･ MDMergerSetSequence
   -------------------------------------- */
MDStatus
MDMergerSetSequence(MDMerger *inMerger, MDSequence *inSequence)
{
	if (inMerger->sequence != inSequence) {
		if (inMerger->sequence != NULL) {
			MDSequenceDetachMerger(inMerger->sequence, inMerger);
			MDSequenceRelease(inMerger->sequence);
		}
		inMerger->sequence = inSequence;
		if (inSequence != NULL) {
			MDSequenceRetain(inSequence);
			MDSequenceAttachMerger(inSequence, inMerger);
		}
		MDMergerReset(inMerger);
	}
	return kMDNoError;
}

/* --------------------------------------
	･ MDMergerGetSequence
   -------------------------------------- */
MDSequence *
MDMergerGetSequence(MDMerger *inMerger)
{
	return inMerger->sequence;
}

/* --------------------------------------
	･ MDMergerReset
   -------------------------------------- */
void
MDMergerReset(MDMerger *inMerger)
{
	int32_t num;
	MDMergerInfo info;
	if (inMerger == NULL || inMerger->sequence == NULL)
		return;
	if (inMerger->info == NULL) {
		inMerger->info = MDArrayNew(sizeof(MDMergerInfo));
		if (inMerger->info == NULL)
			return;
	} else {
		num = MDArrayCount(inMerger->info);
		while (--num >= 0) {
			if (MDArrayFetch(inMerger->info, num, 1, &info) == 1) {
				if (info.track != NULL)
					MDTrackRelease(info.track);
				if (info.ptr != NULL)
					MDPointerRelease(info.ptr);
			}
		}
	}
	num = MDSequenceGetNumberOfTracks(inMerger->sequence);
	MDArraySetCount(inMerger->info, num);
	while (--num >= 0) {
		info.track = MDSequenceGetTrack(inMerger->sequence, num);
		MDTrackRetain(info.track);
		info.eptr = NULL;
		if (info.track != NULL) {
			info.ptr = MDPointerNew(info.track);
			if (info.ptr != NULL) {
				MDPointerSetAutoAdjust(info.ptr, 1);
				info.eptr = MDPointerForward(info.ptr);
			}
		} else info.ptr = NULL;
		info.tick = (info.eptr != NULL ? MDGetTick(info.eptr) : LONG_MAX);
		info.lastTick = -1.0;
		MDArrayReplace(inMerger->info, num, 1, &info);
	}
	inMerger->tick = -1.0;
	inMerger->currentTrack = -1;
	inMerger->eptr = NULL;
}

/* --------------------------------------
	･ MDMergerJumpToTick
   -------------------------------------- */
int
MDMergerJumpToTick(MDMerger *inMerger, MDTickType inTick)
{
	int32_t i, num, minIndex;
	MDTickType minTick;
	MDEvent *eptr;
	if (inMerger == NULL || inMerger->info == NULL)
		return 0;
	num = MDArrayCount(inMerger->info);
	minIndex = -1;
	minTick = kMDMaxTick;
	eptr = NULL;
	for (i = 0; i < num; i++) {
		MDMergerInfo info;
		if (MDArrayFetch(inMerger->info, i, 1, &info) == 1) {
			if (info.ptr != NULL) {
				MDEvent *last_eptr;
				MDPointerJumpToTick(info.ptr, inTick);
				last_eptr = MDPointerBackward(info.ptr);
				info.eptr = MDPointerForward(info.ptr);
				info.tick = (info.eptr != NULL ? MDGetTick(info.eptr) : kMDMaxTick);
				info.lastTick = (last_eptr != NULL ? MDGetTick(last_eptr) : kMDNegativeTick);
				if (info.tick < minTick) {
					minIndex = i;
					minTick = info.tick;
					eptr = info.eptr;
				}
				MDArrayReplace(inMerger->info, i, 1, &info);
			}
		}
	}
	inMerger->eptr = eptr;
	inMerger->tick = minTick;
	inMerger->currentTrack = minIndex;
	return 1;
}

/* --------------------------------------
	･ MDMergerCurrent
   -------------------------------------- */
MDEvent *
MDMergerCurrent(const MDMerger *inMerger)
{
	if (inMerger != NULL)
		return inMerger->eptr;
	else return NULL;
}

/* --------------------------------------
	･ MDMergerForward
   -------------------------------------- */
MDEvent *
MDMergerForward(MDMerger *inMerger)
{
	MDMergerInfo info;
	MDTickType minTick;
	int32_t minIndex, i, num;
	MDEvent *eptr;

	if (inMerger == NULL || inMerger->tick == kMDMaxTick)
		return NULL;
	
	/*  現在位置を持っているトラックをインクリメントする  */
	if (inMerger->info == NULL)
		return NULL;
	if (inMerger->currentTrack != -1) {
		if (MDArrayFetch(inMerger->info, inMerger->currentTrack, 1, &info) != 1)
			return NULL;
		if (info.ptr != NULL) {
			info.eptr = MDPointerForward(info.ptr);
			info.lastTick = info.tick;
			info.tick = (info.eptr != NULL ? MDGetTick(info.eptr) : kMDMaxTick);
		}
		MDArrayReplace(inMerger->info, inMerger->currentTrack, 1, &info);
	}
	
	/*  tick 最小のトラックをさがす  */
	minTick = kMDMaxTick;
	minIndex = -1;
	num = MDArrayCount(inMerger->info);
	for (i = 0; i < num; i++) {
		if (MDArrayFetch(inMerger->info, i, 1, &info) == 1) {
			if (info.tick < minTick) {
				minTick = info.tick;
				minIndex = i;
				eptr = info.eptr;
			}
		}
	}
	inMerger->currentTrack = minIndex;
	if (minTick != kMDMaxTick) {
		inMerger->eptr = eptr;
		inMerger->tick = minTick;
	} else {
		inMerger->currentTrack = -1;
		inMerger->eptr = NULL;
		inMerger->tick = kMDMaxTick;
	}
	return inMerger->eptr;
}

/* --------------------------------------
	･ MDMergerBackward
   -------------------------------------- */
MDEvent *
MDMergerBackward(MDMerger *inMerger)
{
	MDMergerInfo info;
	MDTickType maxLastTick;
	int32_t maxIndex, i, num;
	MDEvent *eptr;
	
	if (inMerger == NULL || inMerger->info == NULL || inMerger->tick == kMDNegativeTick)
		return NULL;
	
	/*  lastTick が最大のトラックを探す  */
	maxLastTick = kMDNegativeTick;
	maxIndex = -1;
	num = MDArrayCount(inMerger->info);
	for (i = num - 1; i >= 0; i--) {
		if (MDArrayFetch(inMerger->info, i, 1, &info) == 1) {
			if (info.lastTick > maxLastTick) {
				maxLastTick = info.lastTick;
				maxIndex = i;
				eptr = info.eptr;
			}
		}
	}

	if (maxIndex == -1) {
		/* 　全部のトラックが先頭位置にある  */
		inMerger->tick = kMDNegativeTick;
		inMerger->eptr = NULL;
		inMerger->currentTrack = -1;
		return NULL;		/*  前のイベントはない  */
	}
	
	/*  そのトラックをデクリメントする  */
	if (MDArrayFetch(inMerger->info, maxIndex, 1, &info) != 1)
		return NULL;
	if (info.ptr != NULL) {
		info.eptr = MDPointerBackward(info.ptr);
		if (info.eptr != NULL) {
			info.tick = MDGetTick(info.eptr);
			eptr = MDPointerBackward(info.ptr);
			info.lastTick = (eptr != NULL ? MDGetTick(eptr) : kMDNegativeTick);
			MDPointerForward(info.ptr);
		}
		MDArrayReplace(inMerger->info, maxIndex, 1, &info);
		inMerger->currentTrack = maxIndex;
		inMerger->eptr = info.eptr;
		inMerger->tick = info.tick;
	}
	return inMerger->eptr;
}

/* --------------------------------------
	･ MDMergerGetCurrentTrack
   -------------------------------------- */
int32_t
MDMergerGetCurrentTrack(MDMerger *inMerger)
{
	if (inMerger != NULL)
		return inMerger->currentTrack;
	else return -1;
}

/* --------------------------------------
	･ MDMergerGetCurrentPositionInTrack
   -------------------------------------- */
int32_t
MDMergerGetCurrentPositionInTrack(MDMerger *inMerger)
{
	MDMergerInfo info;
	if (inMerger != NULL && inMerger->info != NULL
	&& MDArrayFetch(inMerger->info, inMerger->currentTrack, 1, &info) == 1) {
		if (info.ptr != NULL)
			return MDPointerGetPosition(info.ptr);
	}
	return -1;
}

/* --------------------------------------
	･ MDMergerGetTick
   -------------------------------------- */
MDTickType
MDMergerGetTick(MDMerger *inMerger)
{
	if (inMerger != NULL)
		return inMerger->tick;
	else return kMDNegativeTick;
}
#endif

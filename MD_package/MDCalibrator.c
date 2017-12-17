/*
 *  MDCalibrator.c
 *
 *  Created by Toshi Nagata on Sun Jun 17 2001.

   Copyright (c) 2000-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#include "MDHeaders.h"

#include <limits.h>
#include <stdlib.h>

/*  Internal struct: data for individual meta-event  */
typedef union MDCalibratorData {
	MDTimeType	time;
	int32_t		bar;
	short		key;
	short		data1;
} MDCalibratorData;

struct MDCalibrator {
	int32_t				refCount;
	MDSequence *		parent;
	MDTrack *			track;
	MDCalibrator *		next;			/*  List of individual MDCalibrators  */
	MDCalibrator *		chain;			/*  An internal chain of MDCalibrators  */
	MDEventKind			kind;
	short				code;
	MDPointer *			before;
	MDPointer *			after;
	MDTickType			tick_before;
	MDTickType			tick_after;
	MDCalibratorData	data_before;
	MDCalibratorData	data_after;
};

#pragma mark ====== Private functions ======

/* --------------------------------------
	･ MDCalibratorTickToMeasureWithoutJump
   -------------------------------------- */
static void
MDCalibratorTickToMeasureWithoutJump(MDCalibrator *inCalib, MDTickType inTick,
int32_t *outMeasure, int32_t *outBeat, int32_t *outTick)
{
	MDEvent *eptr;
	int32_t tickPerBeat, beatPerMeasure, beat;
	MDTickType theTickBefore;
	int32_t theBarBefore;
	int32_t timebase;

	eptr = MDPointerCurrent(inCalib->before);
	timebase = MDSequenceGetTimebase(inCalib->parent);
	MDEventParseTimeSignature(eptr, timebase, &tickPerBeat, &beatPerMeasure);
	
	if (tickPerBeat == 0 || beatPerMeasure == 0) {
		if (outMeasure != NULL)
			*outMeasure = 0;
		if (outBeat != NULL)
			*outBeat = 0;
		if (outTick != NULL)
			*outTick = 0;
	} else {
		if (eptr == NULL) {
			/*  eptr == NULL の場合、data_before.bar = 1, tick_before = 0 として計算する  */
			theTickBefore = 0;
			theBarBefore = 1;
		} else {
			theTickBefore = inCalib->tick_before;
			theBarBefore = inCalib->data_before.bar;
		}
		
		beat = (inTick - theTickBefore) / tickPerBeat;
		if (outTick != NULL)
			*outTick = (int32_t)(inTick - theTickBefore) - beat * tickPerBeat;
		if (outBeat != NULL)
			*outBeat = beat % beatPerMeasure + 1;
		if (outMeasure != NULL)
			*outMeasure = theBarBefore + beat / beatPerMeasure;
	}
}

/* --------------------------------------
	･ MDCalibratorCalculateTime
   -------------------------------------- */
static MDTimeType
MDCalibratorCalculateTime(MDCalibrator *inCalib, MDTickType inTick)
{
	MDTickType tick_before;
	MDTimeType time_before;
	int32_t timebase;
	float tempo;
	if (inCalib->tick_before >= 0) {
		tick_before = inCalib->tick_before;
		time_before = inCalib->data_before.time;
		tempo = MDCalibratorGetTempo(inCalib);
	} else {
		tempo = 120.0f;
		tick_before = 0;
		time_before = 0;
	}
	timebase = MDSequenceGetTimebase(inCalib->parent);
	return time_before + (MDTimeType)floor(0.5 + (inTick - tick_before) * 60000000.0 / (tempo * timebase));
}

static MDCalibrator *
MDCalibratorInitialize(MDCalibrator *inCalib, MDSequence *inSequence, MDTrack *inTrack, MDEventKind inKind, short inCode)
{
    if (inCalib == NULL)
        return NULL;

	if (inKind == kMDEventTempo || inKind == kMDEventTimeSignature) {
		if (inSequence != NULL)
			inTrack = MDSequenceGetTrack(inSequence, 0);	/*  the conductor track  */
	}
	inCalib->parent = inSequence;
	inCalib->track = inTrack;
	inCalib->next = NULL;
	inCalib->chain = NULL;
	inCalib->kind = inKind;

	MDSequenceRetain(inCalib->parent);
	MDTrackRetain(inCalib->track);
	
	if (inKind == kMDEventMeta || inKind == kMDEventMetaText || inKind == kMDEventMetaMessage
    || inKind == kMDEventNote
	|| inKind == kMDEventControl || inKind == kMDEventKeyPres || inKind == kMDEventData
	|| inKind == kMDEventObject) {
		inCalib->code = inCode;
	} else inCalib->code = -1;

	inCalib->before = MDPointerNew(inTrack);
	if (inCalib->before == NULL) {
		return NULL;
	}
	MDPointerSetAutoAdjust(inCalib->before, 1);
	inCalib->after = MDPointerNew(inTrack);
	if (inCalib->after == NULL) {
		MDPointerRelease(inCalib->before);
        inCalib->before = NULL;
		return NULL;
	}
	MDPointerSetAutoAdjust(inCalib->after, 1);
	MDCalibratorReset(inCalib);
	return inCalib;
}

static MDCalibrator *
MDCalibratorAllocate(MDSequence *inSequence, MDTrack *inTrack, MDEventKind inKind, short inCode)
{
	MDCalibrator *theRef = (MDCalibrator *)malloc(sizeof(MDCalibrator));
	if (theRef == NULL)
		return NULL;	/*  out of memory  */
	if (MDCalibratorInitialize(theRef, inSequence, inTrack, inKind, inCode) == NULL) {
        free(theRef);
        return NULL;
    } else return theRef;
}

static void
MDCalibratorDeallocateChain(MDCalibrator *inCalib)
{
	if (inCalib->chain != NULL)
		MDCalibratorDeallocateChain(inCalib->chain);
	MDPointerRelease(inCalib->before);
	MDPointerRelease(inCalib->after);
	free(inCalib);
}

/* --------------------------------------
	･ MDCalibratorForward
   -------------------------------------- */
static int
MDCalibratorForward(MDCalibrator *inCalib)
{
	MDEvent *eref;
	int32_t measure, beat, tick;

	if (inCalib->track == NULL || inCalib->after == NULL)
        return 0;

	/*  The 'after' position is at the end of track  */
    if (inCalib->tick_after == kMDMaxTick)
		return 0;
	
	MDPointerCopy(inCalib->before, inCalib->after);
	inCalib->tick_before = inCalib->tick_after;
	while ((eref = MDPointerForward(inCalib->after)) != NULL) {
		if (MDGetKind(eref) == inCalib->kind && (inCalib->code == -1 || MDGetCode(eref) == inCalib->code))
			break;
	}
	if (eref == NULL)
		inCalib->tick_after = kMDMaxTick;
	else
		inCalib->tick_after = MDGetTick(eref);

	inCalib->data_before = inCalib->data_after;

	switch (inCalib->kind) {
		case kMDEventTempo:
		//	inCalib->data_before.time = inCalib->data_after.time;
			inCalib->data_after.time = MDCalibratorCalculateTime(inCalib, inCalib->tick_after);
			break;
		case kMDEventTimeSignature:
		//	inCalib->data_before.bar = inCalib->data_after.bar;
			MDCalibratorTickToMeasureWithoutJump(inCalib, inCalib->tick_after, &measure, &beat, &tick);
			if (measure != 0 && (beat > 1 || tick > 0)) {
				/*  小節の途中に拍子記号がある  */
				measure++;
			}
			inCalib->data_after.bar = measure;
			break;
		default:
			if (eref != NULL)
				inCalib->data_after.data1 = MDGetData1(eref);
			break;
	}
	
	return 1;
}

/* --------------------------------------
	･ MDCalibratorBackward
   -------------------------------------- */
static int
MDCalibratorBackward(MDCalibrator *inCalib)
{
	MDEvent *eref;
	int32_t measure, beat, tick;
	MDTimeType time;

    if (inCalib->track == NULL || inCalib->before == NULL)
        return 0;

	/*  The 'before' position is at the beginning of track  */
	if (inCalib->tick_before == kMDNegativeTick)
		return 0;
	
	MDPointerCopy(inCalib->after, inCalib->before);
	inCalib->tick_after = inCalib->tick_before;
	while ((eref = MDPointerBackward(inCalib->before)) != NULL) {
		if (MDGetKind(eref) == inCalib->kind && (inCalib->code == -1 || MDGetCode(eref) == inCalib->code))
			break;
	}
	if (eref == NULL)
		inCalib->tick_before = kMDNegativeTick;
	else
		inCalib->tick_before = MDGetTick(eref);

	inCalib->data_after = inCalib->data_before;
	switch (inCalib->kind) {
		case kMDEventTempo:
		//	inCalib->data_after.time = inCalib->data_before.time;
			/*  仮に data_before.time = 0 として after 位置の時刻を求める  */
			inCalib->data_before.time = 0;
			time = MDCalibratorCalculateTime(inCalib, inCalib->tick_after);
			/*  time == data_after.time になるように data_before.time を調節する  */
			inCalib->data_before.time += inCalib->data_after.time - time;
			break;
		case kMDEventTimeSignature:
		//	inCalib->data_after.bar = inCalib->data_before.bar;
			/*  仮に data_before.bar = 1 としたときの after 位置の小節数を求める */
			inCalib->data_before.bar = 1;
			MDCalibratorTickToMeasureWithoutJump(inCalib, inCalib->tick_after, &measure, &beat, &tick);
			if (measure != 0 && (beat > 1 || tick > 0)) {
				/*  小節の途中に拍子記号がある  */
				measure++;
			}
			/*  after 位置の小節数が data_after.bar と等しくなるように data_before.bar を調節する  */
			inCalib->data_before.bar += inCalib->data_after.bar - measure;
			break;
		default:
			if (eref != NULL)
				inCalib->data_before.data1 = MDGetData1(eref);
			break;
	}
	
	return 1;
}

#pragma mark ====== New/Retain/Release ======

/* --------------------------------------
	･ MDCalibratorNew
   -------------------------------------- */
MDCalibrator *
MDCalibratorNew(MDSequence *inSequence, MDTrack *inTrack, MDEventKind inKind, short inCode)
{
	MDCalibrator *theRef = MDCalibratorAllocate(inSequence, inTrack, inKind, inCode);
	if (theRef == NULL)
		return NULL;	/*  out of memory  */	
	theRef->refCount = 1;
	MDSequenceAttachCalibrator(inSequence, theRef);
	return theRef;
}

/* --------------------------------------
	･ MDCalibratorRetain
   -------------------------------------- */
void
MDCalibratorRetain(MDCalibrator *inCalib)
{
	if (inCalib != NULL)
		inCalib->refCount++;
}

/* --------------------------------------
	･ MDCalibratorRelease
   -------------------------------------- */
void
MDCalibratorRelease(MDCalibrator *inCalib)
{
	if (inCalib != NULL && --inCalib->refCount == 0) {
		if (inCalib->parent != NULL) {
			MDSequenceDetachCalibrator(inCalib->parent, inCalib);
			MDSequenceRelease(inCalib->parent);
		}
		if (inCalib->track != NULL)
			MDTrackRelease(inCalib->track);
		MDCalibratorDeallocateChain(inCalib);
	}
}

#pragma mark ====== Calibrator list manipulations ======

/* --------------------------------------
	･ MDCalibratorAppend
   -------------------------------------- */
int
MDCalibratorIsSupporting(MDCalibrator *inCalib, MDTrack *inTrack, MDEventKind inKind, short inCode)
{
	MDCalibrator *calib;
	for (calib = inCalib; calib != NULL; calib = calib->chain) {
		if (calib->track == inTrack && calib->kind == inKind && calib->code == inCode)
			return 1;
	}
	return 0;
}

/* --------------------------------------
	･ MDCalibratorAppend
   -------------------------------------- */
MDStatus
MDCalibratorAppend(MDCalibrator *inCalib, MDTrack *inTrack, MDEventKind inKind, short inCode)
{
	MDCalibrator *theRef;
	if (inCalib == NULL)
		return kMDErrorBadParameter;
	if (MDCalibratorIsSupporting(inCalib, inTrack, inKind, inCode))
		return kMDNoError;  /*  Already there  */
    if (inCalib->kind == kMDEventNull) {
        /*  In-place substitution  */
        MDCalibrator *next, *chain;
        int32_t refCount;
        next = inCalib->next;
        chain = inCalib->chain;
        refCount = inCalib->refCount;
        if (MDCalibratorInitialize(inCalib, inCalib->parent, inTrack, inKind, inCode) == NULL)
            return kMDErrorOutOfMemory;
        inCalib->next = next;
        inCalib->chain = chain;
        inCalib->refCount = refCount;
        return kMDNoError;
    }
	theRef = MDCalibratorAllocate(inCalib->parent, inTrack, inKind, inCode);
	if (theRef == NULL)
		return kMDErrorOutOfMemory;	
	theRef->refCount = 0;
	while (inCalib->chain != NULL)
		inCalib = inCalib->chain;
	inCalib->chain = theRef;
	return kMDNoError;
}

/* --------------------------------------
	･ MDCalibratorGetInfo
   -------------------------------------- */
MDStatus
MDCalibratorGetInfo(MDCalibrator *inCalib, int index, MDTrack **outTrack, MDEventKind *outKind, short *outCode)
{
    while (inCalib != NULL && --index >= 0)
        inCalib = inCalib->chain;
    if (inCalib != NULL) {
        if (outTrack != NULL)
            *outTrack = inCalib->track;
        if (outKind != NULL)
            *outKind = inCalib->kind;
        if (outCode != NULL)
            *outCode = inCalib->code;
        return kMDNoError;
    } else return kMDErrorBadParameter;
}

/* --------------------------------------
	･ MDCalibratorRemoveAtIndex
   -------------------------------------- */
MDStatus
MDCalibratorRemoveAtIndex(MDCalibrator *inCalib, int index)
{
    MDCalibrator *calib = NULL;
    if (index == 0) {
        /*  The first record in this calibrator chain  */
        if (inCalib->before != NULL)
            MDPointerRelease(inCalib->before);
        if (inCalib->after != NULL)
            MDPointerRelease(inCalib->after);
        if (inCalib->chain != NULL) {
            /*  Copy the next record to this record  */
            calib = inCalib->chain;
            inCalib->chain->next = inCalib->next;
            *inCalib = *(inCalib->chain);
            free(calib); /*  and deallocate the next record  */
        } else {
            /*  Set this record to 'null'  */
            inCalib->before = inCalib->after = NULL;
            inCalib->track = NULL;
            inCalib->kind = kMDEventNull;
            inCalib->code = -1;
            inCalib->tick_before = kMDNegativeTick;
            inCalib->tick_after = kMDNegativeTick;
        }
        return kMDNoError;
    }
    while (inCalib != NULL && --index >= 0) {
        calib = inCalib;
        inCalib = inCalib->chain;
    }
    if (inCalib != NULL) {
        /*  Deallocate this record  */
        if (inCalib->before != NULL)
            MDPointerRelease(inCalib->before);
        if (inCalib->after != NULL)
            MDPointerRelease(inCalib->after);
        calib->chain = inCalib->chain;
        free(inCalib);
        return kMDNoError;
    } else return kMDErrorBadParameter;
}

/* --------------------------------------
	･ MDCalibratorNextInList
   -------------------------------------- */
MDCalibrator *
MDCalibratorNextInList(MDCalibrator *inCalib)
{
	if (inCalib != NULL)
		return inCalib->next;
	else return NULL;
}

/* --------------------------------------
	･ MDCalibratorSetNextInList
   -------------------------------------- */
void
MDCalibratorSetNextInList(MDCalibrator *inCalib, MDCalibrator *inNextCalib)
{
	if (inCalib != NULL)
		inCalib->next = inNextCalib;
}

#pragma mark ====== Moving around ======

/* --------------------------------------
	･ MDCalibratorReset
   -------------------------------------- */
void
MDCalibratorReset(MDCalibrator *inCalib)
{
	if (inCalib == NULL)
		return;
	MDPointerSetTrack(inCalib->before, inCalib->track);
	MDPointerSetPosition(inCalib->before, -1);
	MDPointerSetTrack(inCalib->after, inCalib->track);
	MDPointerSetPosition(inCalib->after, -1);
	inCalib->tick_before = kMDNegativeTick;
	inCalib->tick_after = kMDNegativeTick;
	switch (inCalib->kind) {
		case kMDEventTempo:
			inCalib->data_before.time = inCalib->data_after.time = kMDNegativeTime;
			break;
		case kMDEventTimeSignature:
			inCalib->data_before.bar = inCalib->data_after.bar = 0;
			break;
		case kMDEventKey:
			inCalib->data_before.key = inCalib->data_after.key = 0;
			break;
	}
	if (inCalib->chain != NULL)
		MDCalibratorReset(inCalib->chain);
}

/*  Do 'jump to tick' for a single calibrator unit  */
static void
MDCalibratorJumpToTickSub(MDCalibrator *inCalib, MDTickType inTick)
{
    if (inTick >= inCalib->tick_after) {
        //  末尾に向かって探す
        if (inTick == kMDMaxTick) {
            do {
                MDCalibratorForward(inCalib);
            } while (inCalib->tick_after < kMDMaxTick);
        } else {
            do {
                MDCalibratorForward(inCalib);
            } while (inTick >= inCalib->tick_after);
        }
    } else if (inTick < inCalib->tick_before) {
        //  先頭に向かって探す
        if (inTick < 0) {
            do {
                MDCalibratorBackward(inCalib);
            } while (inCalib->tick_before >= 0);
        } else {
            do {
                MDCalibratorBackward(inCalib);
            } while (inTick < inCalib->tick_before);
        }
    }
}

/* --------------------------------------
	･ MDCalibratorJumpToTick
   -------------------------------------- */
void
MDCalibratorJumpToTick(MDCalibrator *inCalib, MDTickType inTick)
{
    if (inCalib == NULL || inCalib->track == NULL || inCalib->before == NULL)
        return;
    MDCalibratorJumpToTickSub(inCalib, inTick);
	if (inCalib->chain != NULL)
		MDCalibratorJumpToTick(inCalib->chain, inTick);
}

/*  Do 'jump to position in track' for a single calibrator unit  */
static void
MDCalibratorJumpToPositionInTrackSub(MDCalibrator *inCalib, MDTickType inTick, int32_t inPosition, MDTrack *inTrack)
{
    if (inCalib->track == NULL || inCalib->before == NULL)
        return;
    if (inCalib->track != inTrack) {
        MDCalibratorJumpToTickSub(inCalib, inTick);
    } else {
        if (inPosition >= MDPointerGetPosition(inCalib->after)) {
            //  末尾に向かって探す
            if (inPosition >= MDTrackGetNumberOfEvents(inCalib->track)) {
                do {
                    MDCalibratorForward(inCalib);
                } while (inCalib->tick_after < kMDMaxTick);
            } else {
                do {
                    MDCalibratorForward(inCalib);
                } while (inPosition >= MDPointerGetPosition(inCalib->after));
            }
        } else if (inPosition < MDPointerGetPosition(inCalib->before)) {
            //  先頭に向かって探す
            if (inPosition < 0) {
                do {
                    MDCalibratorBackward(inCalib);
                } while (inCalib->tick_before >= 0);
            } else {
                do {
                    MDCalibratorBackward(inCalib);
                } while (inPosition < MDPointerGetPosition(inCalib->before));
            }
        }
    }
    if (inCalib->chain != NULL)
        MDCalibratorJumpToPositionInTrackSub(inCalib->chain, inTick, inPosition, inTrack);
}

/* --------------------------------------
	･ MDCalibratorJumpToPositionInTrack
 -------------------------------------- */
void
MDCalibratorJumpToPositionInTrack(MDCalibrator *inCalib, int32_t inPosition, MDTrack *inTrack)
{
    MDTickType tick;
    MDPointer *pt;
    MDEvent *ep;
    
    if (inCalib == NULL || inCalib->track == NULL || inCalib->before == NULL)
        return;

    if (inPosition < 0)
        tick = kMDNegativeTick;
    else {
        pt = MDPointerNew(inTrack);
        MDPointerSetPosition(pt, inPosition);
        ep = MDPointerCurrent(pt);
        if (ep == NULL)
            tick = kMDMaxTick;
        else tick = MDGetTick(ep);
        MDPointerRelease(pt);
    }
    MDCalibratorJumpToPositionInTrackSub(inCalib, tick, inPosition, inTrack);
}

#pragma mark ====== Getting calibrated information ======

/* --------------------------------------
	･ MDCalibratorMeasureToTick
   -------------------------------------- */
MDTickType
MDCalibratorMeasureToTick(MDCalibrator *inCalib, int32_t inMeasure, int32_t inBeat, int32_t inTick)
{
	MDEvent *eptr;
	int32_t tickPerBeat, beatPerMeasure, timebase, theBarBefore;
	double theTick, theTickBefore;
	
	while (inCalib != NULL) {
		if (inCalib->kind == kMDEventTimeSignature)
			break;
		inCalib = inCalib->chain;
	}
	if (inCalib == NULL)
		return 0;
	
	/*  小節が範囲外の場合  */
	if (inMeasure < 1)
		return kMDNegativeTick;
	if (inMeasure >= INT32_MAX)
		return kMDMaxTick;
	if (inMeasure >= inCalib->data_after.bar) {
		/*  末尾に向かって探す  */
		do {
			MDCalibratorForward(inCalib);
		} while (inMeasure >= inCalib->data_after.bar);
	} else if (inMeasure < inCalib->data_before.bar) {
		/*  先頭に向かって探す  */
		do {
			MDCalibratorBackward(inCalib);
		} while (inMeasure < inCalib->data_before.bar);
	}
	
	/*  １拍の tick 数、１小節の拍数を得る  */
	eptr = MDPointerCurrent(inCalib->before);
	timebase = MDSequenceGetTimebase(inCalib->parent);
	MDEventParseTimeSignature(eptr, timebase, &tickPerBeat, &beatPerMeasure);
	if (eptr == NULL) {
		theBarBefore = 1;
		theTickBefore = 0;
	} else {
		theBarBefore = inCalib->data_before.bar;
		theTickBefore = inCalib->tick_before;
	}
	theTick = theTickBefore + inTick +
		((inBeat - 1) + (inMeasure - theBarBefore) * beatPerMeasure) * tickPerBeat;
	if (theTick > kMDMaxTick)
		return kMDMaxTick;
	else
		return (MDTickType)theTick;
}

/* --------------------------------------
	･ MDCalibratorTickToMeasure
   -------------------------------------- */
void
MDCalibratorTickToMeasure(MDCalibrator *inCalib, MDTickType inTick, int32_t *outMeasure, int32_t *outBeat, int32_t *outTick)
{
	MDCalibratorJumpToTick(inCalib, inTick);
	while (inCalib != NULL) {
		if (inCalib->kind == kMDEventTimeSignature)
			break;
		inCalib = inCalib->chain;
	}
	if (inCalib == NULL)
		return;
	MDCalibratorTickToMeasureWithoutJump(inCalib, inTick, outMeasure, outBeat, outTick);
}

/* --------------------------------------
	･ MDCalibratorGetTempo
   -------------------------------------- */
float
MDCalibratorGetTempo(MDCalibrator *inCalib)
{
	MDEvent *ep;
	while (inCalib != NULL) {
		if (inCalib->kind == kMDEventTempo) {
			ep = MDPointerCurrent(inCalib->before);
			if (ep != NULL)
				return MDGetTempo(ep);
			else break;
		}
		inCalib = inCalib->chain;
	}
	return 120.0f;
}

/* --------------------------------------
	･ MDCalibratorTimeToTick
   -------------------------------------- */
MDTickType
MDCalibratorTimeToTick(MDCalibrator *inCalib, MDTimeType inTime)
{
	MDTickType	tick_before;
	MDTimeType	time_before;
	int32_t timebase;

	while (inCalib != NULL) {
		if (inCalib->kind == kMDEventTempo)
			break;
		inCalib = inCalib->chain;
	}
	if (inCalib == NULL)
		return kMDNegativeTick;
	
	if (inTime >= inCalib->data_after.time) {
		/*  Search forward  */
		while (MDCalibratorForward(inCalib) && inTime >= inCalib->data_after.time) { }
	} else if (inTime < inCalib->data_before.time) {
		/*  Search backward  */
		while (MDCalibratorBackward(inCalib) && inTime < inCalib->data_before.time) { }
	}
	if (inCalib->tick_before >= 0) {
		tick_before = inCalib->tick_before;
		time_before = inCalib->data_before.time;
	} else {
		tick_before = 0;
		time_before = 0;
	}
	timebase = MDSequenceGetTimebase(inCalib->parent);
	return tick_before + (MDTickType)floor(0.5 + (double)(inTime - time_before) * ((double)timebase * MDCalibratorGetTempo(inCalib) / 60000000.0));
}

/* --------------------------------------
	･ MDCalibratorTickToTime
   -------------------------------------- */
MDTimeType
MDCalibratorTickToTime(MDCalibrator *inCalib, MDTickType inTick)
{
	while (inCalib != NULL) {
		if (inCalib->kind == kMDEventTempo)
			break;
		inCalib = inCalib->chain;
	}
	if (inCalib == NULL)
		return (MDTimeType)0;
	MDCalibratorJumpToTick(inCalib, inTick);
	return MDCalibratorCalculateTime(inCalib, inTick);
}

/* --------------------------------------
	･ MDCalibratorGetEvent
   -------------------------------------- */
MDEvent *
MDCalibratorGetEvent(MDCalibrator *inCalib, MDTrack *inTrack, MDEventKind inKind, short inCode)
{
	while (inCalib != NULL) {
		if ((inTrack == NULL || inCalib->track == inTrack)
		&& inCalib->kind == inKind && (inCode == -1 || inCalib->code == inCode))
			break;
		inCalib = inCalib->chain;
	}
	if (inCalib == NULL)
		return NULL;
	else return MDPointerCurrent(inCalib->before);
}

/* --------------------------------------
	･ MDCalibratorGetEventPosition
   -------------------------------------- */
int32_t
MDCalibratorGetEventPosition(MDCalibrator *inCalib, MDTrack *inTrack, MDEventKind inKind, short inCode)
{
	while (inCalib != NULL) {
		if ((inTrack == NULL || inCalib->track == inTrack)
		&& inCalib->kind == inKind && (inCode == -1 || inCalib->code == inCode))
			break;
		inCalib = inCalib->chain;
	}
	if (inCalib == NULL)
		return -1;
	else return MDPointerGetPosition(inCalib->before);
}

/* --------------------------------------
	･ MDCalibratorGetNextEvent
   -------------------------------------- */
MDEvent *
MDCalibratorGetNextEvent(MDCalibrator *inCalib, MDTrack *inTrack, MDEventKind inKind, short inCode)
{
	while (inCalib != NULL) {
		if ((inTrack == NULL || inCalib->track == inTrack)
		&& inCalib->kind == inKind && (inCode == -1 || inCalib->code == inCode))
			break;
		inCalib = inCalib->chain;
	}
	if (inCalib == NULL)
		return NULL;
	else return MDPointerCurrent(inCalib->after);
}

/* --------------------------------------
	･ MDCalibratorCopyPointer
   -------------------------------------- */
MDPointer *
MDCalibratorCopyPointer(MDCalibrator *inCalib, MDTrack *inTrack, MDEventKind inKind, short inCode)
{
	while (inCalib != NULL) {
		if ((inTrack == NULL || inCalib->track == inTrack)
		&& inCalib->kind == inKind && (inCode == -1 || inCalib->code == inCode))
			break;
		inCalib = inCalib->chain;
	}
	if (inCalib == NULL)
		return NULL;
	else {
		MDPointer *pt = MDPointerNew(inCalib->track);
		if (pt == NULL)
			return NULL;
		MDPointerCopy(pt, inCalib->before);
		MDPointerSetAutoAdjust(pt, 1);
		return pt;
	}
}

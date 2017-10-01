/*
   IntGroup.c
   Created by Toshi Nagata, 2000.12.3.

   Copyright (c) 2000-2016 Toshi Nagata.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#include "IntGroup.h"

#include <stdio.h>		/*  for fprintf() in IntGroupDump()  */
#include <stdlib.h>		/*  for malloc(), realloc(), and free()  */
#include <string.h>		/*  for memmove()  */
#include <limits.h>		/*  for INT_MAX  */
#include <stdarg.h>

#pragma mark ====== Private definitions ======

struct IntGroup {
	int			refCount;	/*  the reference count  */
	int			num;		/*  the number of entries  */
	int *		entries;	/*  entries[2*n]: begin point, entries[2*n+1]: end point */
};

typedef short IntGroupOperation;
enum {
	kIntGroupIntersect,
	kIntGroupConvolute,
	kIntGroupDeconvolute
};

#pragma mark ====== Private (static) functions ======

/* --------------------------------------
	･ IntGroupCalcRequiredStorage
   -------------------------------------- */
static int
IntGroupCalcRequiredStorage(int inLength)
{
	return ((inLength * 2 + 3) / 4) * 4 * sizeof(int);
}

/* --------------------------------------
	･ IntGroupAdjustStorage
   -------------------------------------- */
static IntGroupStatus
IntGroupAdjustStorage(IntGroup *psRef, int inLength)
{
	int theOldSize, theNewSize;
	
	theOldSize = IntGroupCalcRequiredStorage(psRef->num);
	theNewSize = IntGroupCalcRequiredStorage(inLength);
	if (theOldSize == theNewSize)
		return 0;
	
	if (theOldSize == 0 && theNewSize != 0) {
		psRef->entries = (int *)malloc(theNewSize);
		if (psRef->entries == NULL)
			return kIntGroupStatusOutOfMemory;
	} else if (theOldSize != 0 && theNewSize == 0) {
		free(psRef->entries);
		psRef->entries = NULL;
	} else {
		int *ptr = (int *)realloc(psRef->entries, theNewSize);
		if (ptr == NULL)
			return kIntGroupStatusOutOfMemory;
		psRef->entries = ptr;
	}
	return kIntGroupStatusNoError;
}

/* --------------------------------------
	･ IntGroupInsertAnEntry
   -------------------------------------- */
static IntGroupStatus
IntGroupInsertAnEntry(IntGroup *psRef, int inIndex, int inBeginPt, int inEndPt)
{
	IntGroupStatus result;
	int moveAmount;
	result = IntGroupAdjustStorage(psRef, psRef->num + 1);
	if (result != kIntGroupStatusNoError)
		return result;	/* out of memory */
	moveAmount = (psRef->num - inIndex) * 2 * sizeof(int);
	if (moveAmount > 0)
		memmove(&(psRef->entries[inIndex * 2 + 2]), &(psRef->entries[inIndex * 2]), moveAmount);
	psRef->entries[inIndex * 2] = inBeginPt;
	psRef->entries[inIndex * 2 + 1] = inEndPt;
	psRef->num++;
	return kIntGroupStatusNoError;
}

/* --------------------------------------
	･ IntGroupDeleteEntries
   -------------------------------------- */
static IntGroupStatus
IntGroupDeleteEntries(IntGroup *psRef, int inStartIndex, int inEndIndex)
{
	IntGroupStatus result;
	int moveAmount;
	if (inStartIndex > inEndIndex)
		return 0;	/*  do nothing  */
	moveAmount = sizeof(int) * 2 * (psRef->num - inEndIndex - 1);
	if (moveAmount > 0)
		memmove(&(psRef->entries[inStartIndex * 2]), &(psRef->entries[inEndIndex * 2 + 2]), moveAmount);
	result = IntGroupAdjustStorage(psRef, psRef->num - (inEndIndex - inStartIndex + 1));
	if (result == kIntGroupStatusNoError)
		psRef->num -= inEndIndex - inStartIndex + 1;
	return result;
}

#pragma mark ====== New/Retain/Release ======

/* --------------------------------------
	･ IntGroupNew
   -------------------------------------- */
IntGroup *
IntGroupNew(void)
{
	IntGroup *psRef = (IntGroup *)malloc(sizeof(*psRef));
	if (psRef == NULL)
		return NULL;	/* out of memory */
	psRef->entries = NULL;
	psRef->num = 0;
	psRef->refCount = 1;
	return psRef;
}

/* --------------------------------------
	･ IntGroupNewFromIntGroup
   -------------------------------------- */
IntGroup *
IntGroupNewFromIntGroup(const IntGroup *src)
{
	IntGroup *dst = IntGroupNew();
	if (dst == NULL)
		return NULL;
	if (IntGroupCopy(dst, src) != kIntGroupStatusNoError) {
		IntGroupRelease(dst);
		return NULL;
	}
	return dst;
}

/* --------------------------------------
	･ IntGroupNewWithPoints
   -------------------------------------- */
IntGroup *
IntGroupNewWithPoints(int start, ...)
{
	va_list ap;
	int length;
	IntGroup *psRef = IntGroupNew();
	if (psRef == NULL)
		return NULL;
	va_start(ap, start);
	while (start >= 0) {
		length = va_arg(ap, int);
		if (IntGroupAdd(psRef, start, length) != 0) {
			IntGroupRelease(psRef);
			return NULL;
		}
		start = va_arg(ap, int);
	}
	va_end(ap);
	return psRef;
}

/* --------------------------------------
	･ IntGroupRetain
   -------------------------------------- */
void
IntGroupRetain(IntGroup *psRef)
{
	if (psRef == NULL)
		return;
	psRef->refCount++;
}

/* --------------------------------------
	･ IntGroupRelease
   -------------------------------------- */
void
IntGroupRelease(IntGroup *psRef)
{
	if (psRef == NULL)
		return;
	if (--psRef->refCount == 0) {
		IntGroupClear(psRef);
		free(psRef);
	}
}

#pragma mark ====== Clear/Copy ======

/* --------------------------------------
	･ IntGroupClear
   -------------------------------------- */
void
IntGroupClear(IntGroup *psRef)
{
	if (psRef == NULL)
		return;
	if (psRef->entries != NULL) {
		free(psRef->entries);
		psRef->entries = NULL;
	}
	psRef->num = 0;
}

/* --------------------------------------
	･ IntGroupCopy
   -------------------------------------- */
IntGroupStatus
IntGroupCopy(IntGroup *psRef1, const IntGroup *psRef2)
{
	IntGroupStatus sts;
	if (psRef1 == NULL || psRef2 == NULL)
		return kIntGroupStatusNoError;
	sts = IntGroupAdjustStorage(psRef1, psRef2->num);
	if (sts == kIntGroupStatusNoError) {
		memmove(psRef1->entries, psRef2->entries, psRef2->num * 2 * sizeof(int));
        psRef1->num = psRef2->num;
    }
	return sts;
}

#pragma mark ====== Point Manipulations ======

/* --------------------------------------
	･ IntGroupLookup
   -------------------------------------- */
int
IntGroupLookup(const IntGroup *psRef, int inPoint, int *outIndex)
{
	int i;
	if (psRef == NULL)
		return 0;
	for (i = 0; i < psRef->num; i++) {
		if (inPoint < psRef->entries[i*2]) {
                        if (outIndex != NULL)
                            *outIndex = i;
                        return 0;
		} else if (inPoint < psRef->entries[i*2+1]) {
                        if (outIndex != NULL)
                            *outIndex = i;
                        return 1;
		}
	}
	if (outIndex != NULL)
		*outIndex = psRef->num;
	return 0;
}

/* --------------------------------------
	･ IntGroupIsEqual
   -------------------------------------- */
int
IntGroupIsEqual(const IntGroup *psRef1, const IntGroup *psRef2)
{
	int i;
	if (psRef1 == NULL || psRef2 == NULL)
		return (psRef1 == psRef2);
	if (psRef1->num != psRef2->num)
		return 0;
	for (i = 0; i < psRef1->num * 2; i++) {
		if (psRef1->entries[i] != psRef2->entries[i])
			return 0;
	}
	return 1;
}

/* --------------------------------------
	･ IntGroupGetCount
   -------------------------------------- */
int
IntGroupGetCount(const IntGroup *psRef)
{
	int i, n;
	if (psRef == NULL)
		return 0;
	n = 0;
	for (i = 0; i < psRef->num; i++)
		n += psRef->entries[i*2+1] - psRef->entries[i*2];
	return n;
}

/* --------------------------------------
	･ IntGroupGetIntervalCount
   -------------------------------------- */
int
IntGroupGetIntervalCount(const IntGroup *psRef)
{
	if (psRef == NULL)
		return 0;
	return psRef->num;
}

/* --------------------------------------
	･ IntGroupAdd
   -------------------------------------- */
IntGroupStatus
IntGroupAdd(IntGroup *psRef, int inStart, int inCount)
{
	int theBeginIndex, theEndIndex;
	int theBeginFlag, theEndFlag;

	if (psRef == NULL || inCount == 0)
		return kIntGroupStatusNoError;
	
	/*  inStart, inStart+inCount が位置指定の中でどこにあるか探す  */
	theBeginFlag = IntGroupLookup(psRef, inStart, &theBeginIndex);
	theEndFlag = IntGroupLookup(psRef, inStart + inCount, &theEndIndex);
	
	if (theBeginFlag) {
		/*  psRef->entries[theBeginIndex*2] <= inStart < psRef->entries[theBeginIndex*2+1]  */
		if (theEndFlag) {
			/*  psRef->entries[theEndIndex*2] <= inStart + inCount
			    < psRef->entries[theEndIndex*2+1]  */
			if (theBeginIndex < theEndIndex) {
				psRef->entries[theBeginIndex*2+1] = psRef->entries[theEndIndex*2+1];
				return IntGroupDeleteEntries(psRef, theBeginIndex + 1, theEndIndex);
			} else return 0;
		} else {
			/*  psRef->entries[(theEndIndex-1)*2+1] <= inStart + inCount
			    < psRef->entries[theEndIndex*2]  */
			psRef->entries[theBeginIndex*2+1] = inStart + inCount;
			return IntGroupDeleteEntries(psRef, theBeginIndex + 1, theEndIndex - 1);
		}
	} else {
		/*  psRef->entries[(theBeginIndex-1)*2+1] <= inStart < psRef->entries[theBeginIndex*2]  */
		int thePoint = 0;
		if (theBeginIndex > 0 && psRef->entries[(theBeginIndex-1)*2+1] == inStart) {
			/*  １つ前のブロックとくっついてしまう  */
			theBeginIndex--;
		} else if (theBeginIndex < psRef->num) {
			thePoint = psRef->entries[theBeginIndex*2];	/*  あとで必要かもしれない  */
			psRef->entries[theBeginIndex*2] = inStart;
		}
		if (theEndFlag) {
			/*  psRef->entries[theEndIndex*2] <= inStart + inCount
			    < psRef->entries[theEndIndex*2+1]  */
			psRef->entries[theBeginIndex*2+1] = psRef->entries[theEndIndex*2+1];
			return IntGroupDeleteEntries(psRef, theBeginIndex + 1, theEndIndex);
		} else {
			/*  psRef->entries[(theEndIndex-1)*2+1] <= inStart + inCount
			    < psRef->entries[theEndIndex*2]  */
			if (theBeginIndex == theEndIndex) {
				if (theBeginIndex < psRef->num)
					psRef->entries[theBeginIndex*2] = thePoint;	/*  元に戻す  */
				return IntGroupInsertAnEntry(psRef, theBeginIndex, inStart, inStart + inCount);
			} else {
				psRef->entries[theBeginIndex*2+1] = inStart + inCount;
				return IntGroupDeleteEntries(psRef, theBeginIndex + 1, theEndIndex - 1);
			}
		}
	}
	
}

/* --------------------------------------
	･ IntGroupRemove
   -------------------------------------- */
IntGroupStatus
IntGroupRemove(IntGroup *psRef, int inStart, int inCount)
{
	int theBeginIndex, theEndIndex;
	int theBeginFlag, theEndFlag;
	
	if (psRef == NULL || inCount == 0)
		return kIntGroupStatusNoError;

	/*  inStart, inStart+inCount が位置指定の中でどこにあるか探す  */
	theBeginFlag = IntGroupLookup(psRef, inStart, &theBeginIndex);
	theEndFlag = IntGroupLookup(psRef, inStart + inCount, &theEndIndex);
	
	if (theBeginFlag) {
		/*  psRef->entries[theBeginIndex*2] <= inStart < psRef->entries[theBeginIndex*2+1]  */
		int thePoint = psRef->entries[theBeginIndex*2];
		if (theEndFlag) {
			/*  psRef->entries[theEndIndex*2] <= inStart + inCount
			    < psRef->entries[theEndIndex*2+1]  */
			psRef->entries[theEndIndex*2] = inStart + inCount;
			if (theBeginIndex == theEndIndex) {
				if (thePoint == inStart)
					return 0;
				else
					return IntGroupInsertAnEntry(psRef, theBeginIndex, thePoint, inStart);
			} else {
				if (thePoint == inStart)
					theBeginIndex--;
				else
					psRef->entries[theBeginIndex*2+1] = inStart;
				return IntGroupDeleteEntries(psRef, theBeginIndex + 1, theEndIndex - 1);
			}
		} else {
			/*  psRef->entries[(theEndIndex-1)*2+1] <= inStart + inCount
			    < psRef->entries[theEndIndex*2]  */
			if (thePoint == inStart)
				theBeginIndex--;
			else
				psRef->entries[theBeginIndex*2+1] = inStart;
			return IntGroupDeleteEntries(psRef, theBeginIndex + 1, theEndIndex - 1);
		}
	} else {
		/*  psRef->entries[(theBeginIndex-1)*2+1] <= inStart < psRef->entries[theBeginIndex*2]  */
		if (theEndFlag) {
			/*  psRef->entries[theEndIndex*2] <= inStart + inCount
			    < psRef->entries[theEndIndex*2+1]  */
			psRef->entries[theEndIndex*2] = inStart + inCount;
			return IntGroupDeleteEntries(psRef, theBeginIndex, theEndIndex - 1);
		} else {
			/*  psRef->entries[(theEndIndex-1)*2+1] <= inStart + inCount
			    < psRef->entries[theEndIndex*2]  */
			return IntGroupDeleteEntries(psRef, theBeginIndex, theEndIndex - 1);
		}
	}
}

/* --------------------------------------
	･ IntGroupReverse
   -------------------------------------- */
IntGroupStatus
IntGroupReverse(IntGroup *psRef, int inStart, int inCount)
{
	int theBeginIndex, theEndIndex, theIndex;
	int theBeginFlag, theEndFlag;
	IntGroupStatus result;
	
	if (psRef == NULL)
		return kIntGroupStatusNoError;

	/*  inStart, inStart+inCount が位置指定の中でどこにあるか探す  */
	theBeginFlag = IntGroupLookup(psRef, inStart, &theBeginIndex);
	theEndFlag = IntGroupLookup(psRef, inStart + inCount, &theEndIndex);

	if (theBeginFlag) {
		/*  psRef->entries[theBeginIndex*2] <= inStart < psRef->entries[theBeginIndex*2+1]  */
		if (psRef->entries[theBeginIndex*2] < inStart) {
			result = IntGroupInsertAnEntry(psRef, theBeginIndex, psRef->entries[theBeginIndex*2], inStart);
			if (result != 0)
				return result;
			theBeginIndex++;
			theEndIndex++;
		}
	} else {
		/*  psRef->entries[(theBeginIndex-1)*2+1] <= inStart < psRef->entries[theBeginIndex*2]  */
		int thePoint;
		if (theBeginIndex == theEndIndex && !theEndFlag)
			thePoint = inStart + inCount;	/* theBeginIndex == mNumberOfEntries の場合を含む  */
		else
			thePoint = psRef->entries[theBeginIndex*2];
		result = IntGroupInsertAnEntry(psRef, theBeginIndex, inStart, thePoint);
		if (result != 0)
			return result;
		theBeginIndex++;
		theEndIndex++;
	}
	
	if (theEndFlag) {
		/*  psRef->entries[theEndIndex*2] <= inStart + inCount
		    < psRef->entries[theEndIndex*2+1] */
		for (theIndex = theBeginIndex; theIndex < theEndIndex; theIndex++) {
			psRef->entries[theIndex*2] = psRef->entries[theIndex*2+1];
			psRef->entries[theIndex*2+1] = psRef->entries[(theIndex+1)*2];
		}
		psRef->entries[theEndIndex*2] = inStart + inCount;
		if (theEndIndex > 0 && psRef->entries[(theEndIndex-1)*2+1] == inStart + inCount) {
			/*  １つ前のブロックとくっついてしまう  */
			psRef->entries[(theEndIndex-1)*2+1] = psRef->entries[theEndIndex*2+1];
			return IntGroupDeleteEntries(psRef, theEndIndex, theEndIndex);
		}
	} else {
		/*  psRef->entries[(theEndIndex-1)*2+1] <= inStart + inCount
		    < psRef->entries[theEndIndex*2]  */
		for (theIndex = theBeginIndex; theIndex < theEndIndex - 1; theIndex++) {
			psRef->entries[theIndex*2] = psRef->entries[theIndex*2+1];
			psRef->entries[theIndex*2+1] = psRef->entries[(theIndex+1)*2];
		}
		if (theIndex == theEndIndex - 1) {
			if (psRef->entries[theIndex*2+1] == inStart + inCount)
				return IntGroupDeleteEntries(psRef, theIndex, theIndex);
			else {
				psRef->entries[theIndex*2] = psRef->entries[theIndex*2+1];
				psRef->entries[theIndex*2+1] = inStart + inCount;
			}
		}
	}
	return 0;
}

/* --------------------------------------
 ･ IntGroupAddIntGroup
 -------------------------------------- */
IntGroupStatus
IntGroupAddIntGroup(IntGroup *psRef1, const IntGroup *psRef2)
{
	int i, n1, n2, result;
	if (psRef1 == NULL || psRef2 == NULL)
		return 0;
	for (i = 0; (n1 = IntGroupGetStartPoint(psRef2, i)) >= 0; i++) {
		n2 = IntGroupGetInterval(psRef2, i);
		if ((result = IntGroupAdd(psRef1, n1, n2)) != 0)
			return result;
	}
	return 0;
}

/* --------------------------------------
 ･ IntGroupRemoveIntGroup
 -------------------------------------- */
IntGroupStatus
IntGroupRemoveIntGroup(IntGroup *psRef1, const IntGroup *psRef2)
{
	int i, n1, n2, result;
	if (psRef1 == NULL || psRef2 == NULL)
		return 0;
	for (i = 0; (n1 = IntGroupGetStartPoint(psRef2, i)) >= 0; i++) {
		n2 = IntGroupGetInterval(psRef2, i);
		if ((result = IntGroupRemove(psRef1, n1, n2)) != 0)
			return result;
	}
	return 0;
}

/* --------------------------------------
 ･ IntGroupReverseIntGroup
 -------------------------------------- */
IntGroupStatus
IntGroupReverseIntGroup(IntGroup *psRef1, const IntGroup *psRef2)
{
	int i, n1, n2, result;
	if (psRef1 == NULL || psRef2 == NULL)
		return 0;
	for (i = 0; (n1 = IntGroupGetStartPoint(psRef2, i)) >= 0; i++) {
		n2 = IntGroupGetInterval(psRef2, i);
		if ((result = IntGroupReverse(psRef1, n1, n2)) != 0)
			return result;
	}
	return 0;
}

/* --------------------------------------
	･ IntGroupGetStartPoint
   -------------------------------------- */
int
IntGroupGetStartPoint(const IntGroup *psRef, int inIndex)
{
	if (psRef == NULL || inIndex < 0 || inIndex >= psRef->num)
		return -1;
	else return psRef->entries[inIndex*2];
}

/* --------------------------------------
	･ IntGroupGetEndPoint
   -------------------------------------- */
int
IntGroupGetEndPoint(const IntGroup *psRef, int inIndex)
{
	if (psRef == NULL || inIndex < 0 || inIndex >= psRef->num)
		return -1;
	else return psRef->entries[inIndex*2+1];
}

/* --------------------------------------
	･ IntGroupGetInterval
   -------------------------------------- */
int
IntGroupGetInterval(const IntGroup *psRef, int inIndex)
{
	if (psRef == NULL || inIndex < 0 || inIndex >= psRef->num)
		return -1;
	else return psRef->entries[inIndex*2+1] - psRef->entries[inIndex*2];
}

/* --------------------------------------
	･ IntGroupGetNthPoint
   -------------------------------------- */
int
IntGroupGetNthPoint(const IntGroup *psRef, int inCount)
{
	int i, n, dn;
	if (psRef == NULL || inCount < 0)
		return -1;
	n = 0;
	for (i = 0; i < psRef->num; i++) {
		dn = psRef->entries[i*2+1] - psRef->entries[i*2];
		if (inCount < n + dn) {
			/*  The inCount-th point is in this interval  */
			return psRef->entries[i*2] + inCount - n;
		}
		n += dn;
	}
	/*  No such point  */
	return -1;
}

/* --------------------------------------
	･ IntGroupLookupPoint
   -------------------------------------- */
int
IntGroupLookupPoint(const IntGroup *psRef, int inPoint)
{
	int i, n;
	if (psRef == NULL || inPoint < 0)
		return -1;
	n = 0;
	for (i = 0; i < psRef->num; i++) {
		if (inPoint >= psRef->entries[i*2] && inPoint < psRef->entries[i*2+1]) {
			return n + inPoint - psRef->entries[i*2];
		}
		n += psRef->entries[i*2+1] - psRef->entries[i*2];
	}
	/*  No such point  */
	return -1;
}

#pragma mark ====== Binary Operations ======

/* --------------------------------------
	･ IntGroupMyIntersect
   -------------------------------------- */
static IntGroupStatus
IntGroupMyIntersect(
	IntGroupOperation inCode,
	const IntGroup *psRef1,
	const IntGroup *psRef2,
	IntGroup *psRef3)
{
	int base = 0;
	int i, j, offset1, offset2, where;
	int theBeginIndex, theEndIndex;
	int theBeginFlag, theEndFlag;
	const int *ptr;
	IntGroupStatus result = kIntGroupStatusNoError;

	IntGroupClear(psRef3);
	offset1 = offset2 = 0;
	where = 0;

	for (i = 0; result == 0 && i < psRef2->num; i++) {

		int beginPt, endPt;
		int newBeginPt, newEndPt;

		ptr = &(psRef2->entries[i * 2]);
		switch (inCode) {
			case kIntGroupIntersect:
				break;	/* offset1 = offset2 = 0  */
			case kIntGroupConvolute:
				offset1 = base - ptr[0];
				offset2 = -offset1;
				break;
			case kIntGroupDeconvolute:
				offset2 = base - ptr[0];
				break;
		}
		beginPt = ptr[0] + offset1;
		endPt = ptr[1] + offset1;
		theBeginFlag = IntGroupLookup(psRef1, beginPt, &theBeginIndex);
		theEndFlag = IntGroupLookup(psRef1, endPt, &theEndIndex);

		if (theBeginIndex == psRef1->num)
			break;	/*  もう加えるべき区間はない  */

		if (theBeginFlag) {
			newBeginPt = beginPt + offset2;
		} else {
			newBeginPt = psRef1->entries[theBeginIndex * 2] + offset2;
		}
		if (theEndFlag && theBeginIndex == theEndIndex) {
			newEndPt = endPt + offset2;
		} else if (!theEndFlag && theBeginIndex == theEndIndex) {
			newEndPt = newBeginPt;	/* null interval */
		} else {
			newEndPt = psRef1->entries[theBeginIndex * 2 + 1] + offset2;
		}
		/*  直前の区間と連続していないかどうかチェック  */
                if (where > 0 && newBeginPt == psRef3->entries[where * 2 - 1]) {
			psRef3->entries[where * 2 - 1] = newEndPt;
		} else if (newBeginPt < newEndPt) {
                        result = IntGroupInsertAnEntry(psRef3, where++, newBeginPt, newEndPt);
		}
		if (result == kIntGroupStatusNoError) {
			for (j = theBeginIndex + 1; j < theEndIndex; j++) {
				result = IntGroupInsertAnEntry(psRef3,
									where++,
									psRef1->entries[j * 2] + offset2,
									psRef1->entries[j * 2 + 1] + offset2);
				if (result != kIntGroupStatusNoError)
					break;
			}
		}
		if (result == kIntGroupStatusNoError) {
			if (theEndFlag && theBeginIndex < theEndIndex
			&& psRef1->entries[theEndIndex * 2] < endPt)
				result = IntGroupInsertAnEntry(psRef3,
									where++,
									psRef1->entries[theEndIndex * 2] + offset2,
									endPt + offset2);
		}

		base += ptr[1] - ptr[0];
	}

	return result;
}

/* --------------------------------------
	･ IntGroupUnion
   -------------------------------------- */
IntGroupStatus
IntGroupUnion(const IntGroup *psRef1, const IntGroup *psRef2, IntGroup *psRef3)
{
	int i, startPt;
	IntGroupStatus result;
	result = IntGroupCopy(psRef3, psRef2);
	if (result != kIntGroupStatusNoError)
		return result;
	for (i = 0; i < psRef1->num; i++) {
		startPt = psRef1->entries[i*2];
		result = IntGroupAdd(psRef3, startPt, psRef1->entries[i*2+1] - startPt);
		if (result != kIntGroupStatusNoError)
			return result;
	}
	return kIntGroupStatusNoError;
}

/* --------------------------------------
	･ IntGroupIntersect
   -------------------------------------- */
IntGroupStatus
IntGroupIntersect(const IntGroup *psRef1, const IntGroup *psRef2, IntGroup *psRef3)
{
	return IntGroupMyIntersect(kIntGroupIntersect, psRef1, psRef2, psRef3);
}

/* --------------------------------------
	･ IntGroupXor
   -------------------------------------- */
IntGroupStatus
IntGroupXor(const IntGroup *psRef1, const IntGroup *psRef2, IntGroup *psRef3)
{
    IntGroupStatus result;
    int i, startPt;
    result = IntGroupCopy(psRef3, psRef1);
    if (result != kIntGroupStatusNoError)
        return result;
    for (i = 0; i < psRef2->num; i++) {
        startPt = psRef2->entries[i*2];
        result = IntGroupReverse(psRef3, startPt, psRef2->entries[i*2+1] - startPt);
        if (result != kIntGroupStatusNoError)
            return result;
    }
    return kIntGroupStatusNoError;
}

/* --------------------------------------
	･ IntGroupConvolute
   -------------------------------------- */
IntGroupStatus
IntGroupConvolute(const IntGroup *psRef1, const IntGroup *psRef2, IntGroup *psRef3)
{
	return IntGroupMyIntersect(kIntGroupConvolute, psRef1, psRef2, psRef3);
}

/* --------------------------------------
	･ IntGroupDeconvolute
   -------------------------------------- */
IntGroupStatus
IntGroupDeconvolute(const IntGroup *psRef1, const IntGroup *psRef2, IntGroup *psRef3)
{
	return IntGroupMyIntersect(kIntGroupDeconvolute, psRef1, psRef2, psRef3);
}

/* --------------------------------------
	･ IntGroupDifference
   -------------------------------------- */
IntGroupStatus
IntGroupDifference(const IntGroup *psRef1, const IntGroup *psRef2, IntGroup *psRef3)
{
    IntGroupStatus result;
    int i, startPt;
    result = IntGroupCopy(psRef3, psRef1);
    if (result != kIntGroupStatusNoError)
        return result;
    for (i = 0; i < psRef2->num; i++) {
        startPt = psRef2->entries[i*2];
        result = IntGroupRemove(psRef3, startPt, psRef2->entries[i*2+1] - startPt);
        if (result != kIntGroupStatusNoError)
            return result;
    }
    return kIntGroupStatusNoError;
}

/* --------------------------------------
	･ IntGroupNegate
   -------------------------------------- */
IntGroupStatus
IntGroupNegate(const IntGroup *psRef1, IntGroup *psRef2)
{
	int i;

	IntGroupCopy(psRef2, psRef1);
	if (psRef1->num == 0) {
		//  空集合
		return IntGroupInsertAnEntry(psRef2, 0, 0, INT_MAX);
	}
	
	if (psRef1->entries[0] == 0) {
		for (i = 0; i < psRef1->num - 1; i++) {
			psRef2->entries[i*2] = psRef1->entries[i*2+1];
			psRef2->entries[i*2+1] = psRef1->entries[(i+1)*2];
		}
		if (psRef1->entries[i*2+1] != INT_MAX) {
			psRef2->entries[i*2] = psRef1->entries[i*2+1];
			psRef2->entries[i*2+1] = INT_MAX;
		} else return IntGroupDeleteEntries(psRef2, i, i);
	} else {
		psRef2->entries[0] = 0;
		psRef2->entries[1] = psRef1->entries[0];
		for (i = 1; i < psRef1->num; i++) {
			psRef2->entries[i*2] = psRef1->entries[(i-1)*2+1];
			psRef2->entries[i*2+1] = psRef1->entries[i*2];
		}
		if (psRef1->entries[(i-1)*2+1] != INT_MAX) {
			return IntGroupInsertAnEntry(psRef2, i, psRef1->entries[(i-1)*2+1], INT_MAX);
		}
	}
	return kIntGroupStatusNoError;
}

/* --------------------------------------
    ･ IntGroupMinimum
 -------------------------------------- */
int
IntGroupMinimum(const IntGroup *psRef)
{
	if (psRef == NULL || psRef->num == 0)
		return -1;
	return psRef->entries[0];
}

/* --------------------------------------
	 ･ IntGroupMaximum
 -------------------------------------- */
int
IntGroupMaximum(const IntGroup *psRef)
{
	if (psRef == NULL || psRef->num == 0)
		return -1;
	return psRef->entries[psRef->num*2-1] - 1;
}

/* --------------------------------------
	･ IntGroupOffset
   -------------------------------------- */
IntGroupStatus
IntGroupOffset(IntGroup *psRef, int offset)
{
	int i;
	if (psRef == NULL || psRef->num == 0)
		return kIntGroupStatusNoError;
	if (psRef->entries[0] + offset < 0)
		return kIntGroupStatusOutOfRange;  /*  Negative number is not allowed  */
	for (i = 0; i < psRef->num; i++) {
		psRef->entries[i*2] += offset;
		psRef->entries[i*2+1] += offset;
	}
	return kIntGroupStatusNoError;
}

#pragma mark ====== Debugging ======

char *
IntGroupInspect(const IntGroup *pset)
{
	int i, sp, ep, len, len2, size;
	char buf[64], *s;
	if (pset == NULL)
		return strdup("(null)");
	size = 64;
	s = (char *)malloc(size);
	strcpy(s, "IntGroup[");
	if (pset->num == 0) {
		strcat(s, "]");
		return s;
	}
	len = (int)strlen(s);
	for (i = 0; i < pset->num; i++) {
		const char *sep = (i == pset->num - 1 ? "]" : ", ");
		sp = pset->entries[i * 2];
		ep = pset->entries[i * 2 + 1];
		if (ep > sp + 1)
			snprintf(buf, sizeof buf, "%d..%d%s", sp, ep - 1, sep);
		else
			snprintf(buf, sizeof buf, "%d%s", sp, sep);
		len2 = (int)strlen(buf);
		if (len + len2 >= size - 1) {
			size += 64;
			s = (char *)realloc(s, size);
			if (s == NULL)
				return NULL;  /*  Out of memory  */
		}
		len += len2;
		strcat(s, buf);
	}
	return s;  /*  The caller needs to free the return value  */
}

/* --------------------------------------
	･ IntGroupDump
   -------------------------------------- */
void
IntGroupDump(const IntGroup *pset)
{
    int i, n, m;
    fprintf(stderr, "IntGroup[%p]: ", pset);
    for (i = 0; i < pset->num; i++) {
        n = pset->entries[i*2];
        m = pset->entries[i*2+1];
        fprintf(stderr, "%d", n);
        if (m > n + 1)
            fprintf(stderr, "-%d", m-1);
        if (i < pset->num - 1)
            fprintf(stderr, ",");
    }
    fprintf(stderr, "\n");
}

#pragma mark ====== Iterators ======

/* --------------------------------------
	･ IntGroupIteratorNew
   -------------------------------------- */
IntGroupIterator *
IntGroupIteratorNew(IntGroup *psRef)
{
	IntGroupIterator *piRef = (IntGroupIterator *)malloc(sizeof(*piRef));
	if (piRef == NULL)
		return NULL;	/* out of memory */
	IntGroupIteratorInit(psRef, piRef);
	piRef->refCount = 1;
	return piRef;
}

/* --------------------------------------
	･ IntGroupIteratorInit
   -------------------------------------- */
IntGroupIterator *
IntGroupIteratorInit(IntGroup *psRef, IntGroupIterator *piRef)
{
	piRef->intGroup = psRef;
	IntGroupRetain(psRef);
	piRef->index = -1;
	piRef->position = -1;
	piRef->refCount = -1;
	return piRef;
}

/* --------------------------------------
	･ IntGroupIteratorRetain
   -------------------------------------- */
void
IntGroupIteratorRetain(IntGroupIterator *piRef)
{
	if (piRef == NULL)
		return;
	else if (piRef->refCount < 0)
		piRef->refCount--;
	else
		piRef->refCount++;
}

/* --------------------------------------
	･ IntGroupIteratorRelease
   -------------------------------------- */
void
IntGroupIteratorRelease(IntGroupIterator *piRef)
{
	if (piRef == NULL)
		return;
	else if (piRef->refCount < 0) {
		if (++piRef->refCount == 0)
			IntGroupRelease(piRef->intGroup);
	} else {
		if (--piRef->refCount == 0) {
			IntGroupRelease(piRef->intGroup);
			free(piRef);
		}
	}
}

void
IntGroupIteratorReset(IntGroupIterator *piRef)
{
    if (piRef == NULL)
        return;
    piRef->index = -1;
    piRef->position = -1;
}

void
IntGroupIteratorResetAtLast(IntGroupIterator *piRef)
{
    if (piRef == NULL || piRef->intGroup == NULL)
        return;
    piRef->index = piRef->intGroup->num - 1;
    if (piRef->index >= 0)
        piRef->position = piRef->intGroup->entries[piRef->intGroup->num * 2 - 1];
    else piRef->position = -1;
}

int
IntGroupIteratorNext(IntGroupIterator *piRef)
{
    if (piRef == NULL || piRef->intGroup == NULL || piRef->intGroup->num == 0 || piRef->index >= piRef->intGroup->num)
        return -1;
    if (piRef->position < 0) {
        piRef->index = 0;
        piRef->position = piRef->intGroup->entries[0];
        return piRef->position;
    } else {
        piRef->position++;
        if (piRef->intGroup->entries[piRef->index * 2 + 1] > piRef->position)
            return piRef->position;
        if (piRef->index == piRef->intGroup->num - 1) {
            piRef->index = piRef->intGroup->num;
            return -1;
        } else {
            piRef->index++;
            piRef->position = piRef->intGroup->entries[piRef->index * 2];
            return piRef->position;
        }
    }
}

int
IntGroupIteratorLast(IntGroupIterator *piRef)
{
    if (piRef == NULL || piRef->intGroup == NULL || piRef->intGroup->num == 0 || piRef->index < 0)
        return -1;
    piRef->position--;
    if (piRef->intGroup->entries[piRef->index * 2] <= piRef->position)
        return piRef->position;
    if (piRef->index == 0) {
        piRef->index = -1;
        piRef->position = -1;
        return -1;
    } else {
        piRef->index--;
        piRef->position = piRef->intGroup->entries[piRef->index * 2 + 1] - 1;
        return piRef->position;
    }
}

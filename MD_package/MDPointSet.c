/*
   MDPointSet.c
   Created by Toshi Nagata, 2000.12.3.

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

#include <stdlib.h>		/*  for malloc(), realloc(), and free()  */
#include <string.h>		/*  for memmove()  */
#include <limits.h>		/*  for LONG_MAX  */

#ifdef __MWERKS__
#pragma mark ====== Private definitions ======
#endif

struct MDPointSet {
	long			refCount;	/*  the reference count  */
	long			num;		/*  the number of entries  */
	long *			entries;	/*  entries[2*n]: begin point, entries[2*n+1]: end point */
};

typedef short MDPointSetOperation;
enum {
	kMDPointSetIntersect,
	kMDPointSetConvolute,
	kMDPointSetDeconvolute
};

#ifdef __MWERKS__
#pragma mark ====== Private (static) functions ======
#endif

/* --------------------------------------
	･ MDPointSetCalcRequiredStorage
   -------------------------------------- */
static long
MDPointSetCalcRequiredStorage(long inLength)
{
	return ((inLength * 2 + 3) / 4) * 4 * sizeof(long);
}

/* --------------------------------------
	･ MDPointSetAdjustStorage
   -------------------------------------- */
static MDStatus
MDPointSetAdjustStorage(MDPointSet *psRef, long inLength)
{
	long theOldSize, theNewSize;
	
	theOldSize = MDPointSetCalcRequiredStorage(psRef->num);
	theNewSize = MDPointSetCalcRequiredStorage(inLength);
	if (theOldSize == theNewSize)
		return 0;
	
	if (theOldSize == 0 && theNewSize != 0) {
		psRef->entries = (long *)malloc(theNewSize);
		if (psRef->entries == NULL)
			return kMDErrorOutOfMemory;
	} else if (theOldSize != 0 && theNewSize == 0) {
		free(psRef->entries);
		psRef->entries = NULL;
	} else {
		long *ptr = (long *)realloc(psRef->entries, theNewSize);
		if (ptr == NULL)
			return kMDErrorOutOfMemory;
		psRef->entries = ptr;
	}
	return kMDNoError;
}

/* --------------------------------------
	･ MDPointSetInsertAnEntry
   -------------------------------------- */
static MDStatus
MDPointSetInsertAnEntry(MDPointSet *psRef, long inIndex, long inBeginPt, long inEndPt)
{
	MDStatus result;
	long moveAmount;
	result = MDPointSetAdjustStorage(psRef, psRef->num + 1);
	if (result != kMDNoError)
		return result;	/* out of memory */
	moveAmount = (psRef->num - inIndex) * 2 * sizeof(long);
	if (moveAmount > 0)
		memmove(&(psRef->entries[inIndex * 2 + 2]), &(psRef->entries[inIndex * 2]), moveAmount);
	psRef->entries[inIndex * 2] = inBeginPt;
	psRef->entries[inIndex * 2 + 1] = inEndPt;
	psRef->num++;
	return kMDNoError;
}

/* --------------------------------------
	･ MDPointSetDeleteEntries
   -------------------------------------- */
static MDStatus
MDPointSetDeleteEntries(MDPointSet *psRef, long inStartIndex, long inEndIndex)
{
	MDStatus result;
	long moveAmount;
	if (inStartIndex > inEndIndex)
		return 0;	/*  do nothing  */
	moveAmount = sizeof(long) * 2 * (psRef->num - inEndIndex - 1);
	if (moveAmount > 0)
		memmove(&(psRef->entries[inStartIndex * 2]), &(psRef->entries[inEndIndex * 2 + 2]), moveAmount);
	result = MDPointSetAdjustStorage(psRef, psRef->num - (inEndIndex - inStartIndex + 1));
	if (result == kMDNoError)
		psRef->num -= inEndIndex - inStartIndex + 1;
	return result;
}

/* --------------------------------------
	･ MDPointSetMyIntersect
   -------------------------------------- */
static MDStatus
MDPointSetMyIntersect(
	MDPointSetOperation inCode,
	const MDPointSet *psRef1,
	const MDPointSet *psRef2,
	MDPointSet *psRef3)
{
	long base = 0;
	long i, j, offset1, offset2, where;
	long theBeginIndex, theEndIndex;
	int theBeginFlag, theEndFlag;
	const long *ptr;
	MDStatus result = kMDNoError;

	MDPointSetClear(psRef3);
	offset1 = offset2 = 0;
	where = 0;

	for (i = 0; result == 0 && i < psRef2->num; i++) {

		long beginPt, endPt;
		long newBeginPt, newEndPt;

		ptr = &(psRef2->entries[i * 2]);
		switch (inCode) {
			case kMDPointSetIntersect:
				break;	/* offset1 = offset2 = 0  */
			case kMDPointSetConvolute:
				offset1 = base - ptr[0];
				offset2 = -offset1;
				break;
			case kMDPointSetDeconvolute:
				offset2 = base - ptr[0];
				break;
		}
		beginPt = ptr[0] + offset1;
		endPt = ptr[1] + offset1;
		theBeginFlag = MDPointSetLookup(psRef1, beginPt, &theBeginIndex);
		theEndFlag = MDPointSetLookup(psRef1, endPt, &theEndIndex);

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
                        result = MDPointSetInsertAnEntry(psRef3, where++, newBeginPt, newEndPt);
		}
		if (result == kMDNoError) {
			for (j = theBeginIndex + 1; j < theEndIndex; j++) {
				result = MDPointSetInsertAnEntry(psRef3,
									where++,
									psRef1->entries[j * 2] + offset2,
									psRef1->entries[j * 2 + 1] + offset2);
				if (result != kMDNoError)
					break;
			}
		}
		if (result == kMDNoError) {
			if (theEndFlag && theBeginIndex < theEndIndex
			&& psRef1->entries[theEndIndex * 2] < endPt)
				result = MDPointSetInsertAnEntry(psRef3,
									where++,
									psRef1->entries[theEndIndex * 2] + offset2,
									endPt + offset2);
		}

		base += ptr[1] - ptr[0];
	}

	/*  *****   debug   *****  */
/*
	FILE *fp;
	fp = ::fopen("intersect.out", "at");
	switch (inCode) {
		case code_Intersect: ::fprintf(fp, "Intersect:\n"); break;
		case code_Convolute: ::fprintf(fp, "Convolute:\n"); break;
		case code_Deconvolute: ::fprintf(fp, "Deconvolute:\n"); break;
	}
	for (i = 0; i < psRef1.mNumberOfEntries; i++) {
		::fprintf(fp, "%c%ld %ld", (i == 0 ? '(' : ' '),
			(long)psRef1.mEntries[i].beginPt,
			(long)psRef1.mEntries[i].endPt);
	}
	::fprintf(fp, ")\n");
	for (i = 0; i < psRef2.mNumberOfEntries; i++) {
		::fprintf(fp, "%c%ld %ld", (i == 0 ? '(' : ' '),
			(long)psRef2.mEntries[i].beginPt,
			(long)psRef2.mEntries[i].endPt);
	}
	::fprintf(fp, ")\n");
	for (i = 0; i < psRef3.mNumberOfEntries; i++) {
		::fprintf(fp, "%c%ld %ld", (i == 0 ? '(' : ' '),
			(long)psRef3.mEntries[i].beginPt,
			(long)psRef3.mEntries[i].endPt);
	}
	::fprintf(fp, ")\n");
	::fclose(fp);
*/
	/*  *********************  */
	
	return result;
}

#ifdef __MWERKS__
#pragma mark ====== New/Retain/Release ======
#endif

/* --------------------------------------
	･ MDPointSetNew
   -------------------------------------- */
MDPointSet *
MDPointSetNew(void)
{
	MDPointSet *psRef = (MDPointSet *)malloc(sizeof(*psRef));
	if (psRef == NULL)
		return NULL;	/* out of memory */
	psRef->entries = NULL;
	psRef->num = 0;
	psRef->refCount = 1;
	return psRef;
}

/* --------------------------------------
	･ MDPointSetRetain
   -------------------------------------- */
void
MDPointSetRetain(MDPointSet *psRef)
{
	if (psRef == NULL)
		return;
	psRef->refCount++;
}

/* --------------------------------------
	･ MDPointSetRelease
   -------------------------------------- */
void
MDPointSetRelease(MDPointSet *psRef)
{
	if (psRef == NULL)
		return;
	if (--psRef->refCount == 0) {
		MDPointSetClear(psRef);
		free(psRef);
	}
}

#ifdef __MWERKS__
#pragma mark ====== Clear/Copy ======
#endif
/* --------------------------------------
	･ MDPointSetClear
   -------------------------------------- */
void
MDPointSetClear(MDPointSet *psRef)
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
	･ MDPointSetCopy
   -------------------------------------- */
MDStatus
MDPointSetCopy(MDPointSet *psRef1, const MDPointSet *psRef2)
{
	MDStatus sts;
	if (psRef1 == NULL || psRef2 == NULL)
		return kMDNoError;
	sts = MDPointSetAdjustStorage(psRef1, psRef2->num);
	if (sts == kMDNoError) {
		memmove(psRef1->entries, psRef2->entries, psRef2->num * 2 * sizeof(long));
        psRef1->num = psRef2->num;
    }
	return sts;
}

#ifdef __MWERKS__
#pragma mark ====== Point Manipulations ======
#endif

/* --------------------------------------
	･ MDPointSetLookup
   -------------------------------------- */
int
MDPointSetLookup(const MDPointSet *psRef, long inPoint, long *outIndex)
{
	long i;
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
	･ MDPointSetGetCount
   -------------------------------------- */
long
MDPointSetGetCount(const MDPointSet *psRef)
{
	long i, n;
	if (psRef == NULL)
		return 0;
	n = 0;
	for (i = 0; i < psRef->num; i++)
		n += psRef->entries[i*2+1] - psRef->entries[i*2];
	return n;
}

/* --------------------------------------
	･ MDPointSetGetIntervalCount
   -------------------------------------- */
long
MDPointSetGetIntervalCount(const MDPointSet *psRef)
{
	if (psRef == NULL)
		return 0;
	return psRef->num;
}

/* --------------------------------------
	･ MDPointSetAdd
   -------------------------------------- */
MDStatus
MDPointSetAdd(MDPointSet *psRef, long inStart, long inCount)
{
	long theBeginIndex, theEndIndex;
	int theBeginFlag, theEndFlag;

	if (psRef == NULL)
		return kMDNoError;
	
	/*  inStart, inStart+inCount が位置指定の中でどこにあるか探す  */
	theBeginFlag = MDPointSetLookup(psRef, inStart, &theBeginIndex);
	theEndFlag = MDPointSetLookup(psRef, inStart + inCount, &theEndIndex);
	
	if (theBeginFlag) {
		/*  psRef->entries[theBeginIndex*2] <= inStart < psRef->entries[theBeginIndex*2+1]  */
		if (theEndFlag) {
			/*  psRef->entries[theEndIndex*2] <= inStart + inCount
			    < psRef->entries[theEndIndex*2+1]  */
			if (theBeginIndex < theEndIndex) {
				psRef->entries[theBeginIndex*2+1] = psRef->entries[theEndIndex*2+1];
				return MDPointSetDeleteEntries(psRef, theBeginIndex + 1, theEndIndex);
			} else return 0;
		} else {
			/*  psRef->entries[(theEndIndex-1)*2+1] <= inStart + inCount
			    < psRef->entries[theEndIndex*2]  */
			psRef->entries[theBeginIndex*2+1] = inStart + inCount;
			return MDPointSetDeleteEntries(psRef, theBeginIndex + 1, theEndIndex - 1);
		}
	} else {
		/*  psRef->entries[(theBeginIndex-1)*2+1] <= inStart < psRef->entries[theBeginIndex*2]  */
		long thePoint = 0;
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
			return MDPointSetDeleteEntries(psRef, theBeginIndex + 1, theEndIndex);
		} else {
			/*  psRef->entries[(theEndIndex-1)*2+1] <= inStart + inCount
			    < psRef->entries[theEndIndex*2]  */
			if (theBeginIndex == theEndIndex) {
				if (theBeginIndex < psRef->num)
					psRef->entries[theBeginIndex*2] = thePoint;	/*  元に戻す  */
				return MDPointSetInsertAnEntry(psRef, theBeginIndex, inStart, inStart + inCount);
			} else {
				psRef->entries[theBeginIndex*2+1] = inStart + inCount;
				return MDPointSetDeleteEntries(psRef, theBeginIndex + 1, theEndIndex - 1);
			}
		}
	}
	
}

/* --------------------------------------
	･ MDPointSetRemove
   -------------------------------------- */
MDStatus
MDPointSetRemove(MDPointSet *psRef, long inStart, long inCount)
{
	long theBeginIndex, theEndIndex;
	int theBeginFlag, theEndFlag;
	
	if (psRef == NULL)
		return kMDNoError;

	/*  inStart, inStart+inCount が位置指定の中でどこにあるか探す  */
	theBeginFlag = MDPointSetLookup(psRef, inStart, &theBeginIndex);
	theEndFlag = MDPointSetLookup(psRef, inStart + inCount, &theEndIndex);
	
	if (theBeginFlag) {
		/*  psRef->entries[theBeginIndex*2] <= inStart < psRef->entries[theBeginIndex*2+1]  */
		long thePoint = psRef->entries[theBeginIndex*2];
		if (theEndFlag) {
			/*  psRef->entries[theEndIndex*2] <= inStart + inCount
			    < psRef->entries[theEndIndex*2+1]  */
			psRef->entries[theEndIndex*2] = inStart + inCount;
			if (theBeginIndex == theEndIndex) {
				if (thePoint == inStart)
					return 0;
				else
					return MDPointSetInsertAnEntry(psRef, theBeginIndex, thePoint, inStart);
			} else {
				if (thePoint == inStart)
					theBeginIndex--;
				else
					psRef->entries[theBeginIndex*2+1] = inStart;
				return MDPointSetDeleteEntries(psRef, theBeginIndex + 1, theEndIndex - 1);
			}
		} else {
			/*  psRef->entries[(theEndIndex-1)*2+1] <= inStart + inCount
			    < psRef->entries[theEndIndex*2]  */
			if (thePoint == inStart)
				theBeginIndex--;
			else
				psRef->entries[theBeginIndex*2+1] = inStart;
			return MDPointSetDeleteEntries(psRef, theBeginIndex + 1, theEndIndex - 1);
		}
	} else {
		/*  psRef->entries[(theBeginIndex-1)*2+1] <= inStart < psRef->entries[theBeginIndex*2]  */
		if (theEndFlag) {
			/*  psRef->entries[theEndIndex*2] <= inStart + inCount
			    < psRef->entries[theEndIndex*2+1]  */
			psRef->entries[theEndIndex*2] = inStart + inCount;
			return MDPointSetDeleteEntries(psRef, theBeginIndex, theEndIndex - 1);
		} else {
			/*  psRef->entries[(theEndIndex-1)*2+1] <= inStart + inCount
			    < psRef->entries[theEndIndex*2]  */
			return MDPointSetDeleteEntries(psRef, theBeginIndex, theEndIndex - 1);
		}
	}
}

/* --------------------------------------
	･ MDPointSetReverse
   -------------------------------------- */
MDStatus
MDPointSetReverse(MDPointSet *psRef, long inStart, long inCount)
{
	long theBeginIndex, theEndIndex, theIndex;
	int theBeginFlag, theEndFlag;
	MDStatus result;
	
	if (psRef == NULL)
		return kMDNoError;

	/*  inStart, inStart+inCount が位置指定の中でどこにあるか探す  */
	theBeginFlag = MDPointSetLookup(psRef, inStart, &theBeginIndex);
	theEndFlag = MDPointSetLookup(psRef, inStart + inCount, &theEndIndex);

	if (theBeginFlag) {
		/*  psRef->entries[theBeginIndex*2] <= inStart < psRef->entries[theBeginIndex*2+1]  */
		if (psRef->entries[theBeginIndex*2] < inStart) {
			result = MDPointSetInsertAnEntry(psRef, theBeginIndex, psRef->entries[theBeginIndex*2], inStart);
			if (result != 0)
				return result;
			theBeginIndex++;
			theEndIndex++;
		}
	} else {
		/*  psRef->entries[(theBeginIndex-1)*2+1] <= inStart < psRef->entries[theBeginIndex*2]  */
		long thePoint;
		if (theBeginIndex == theEndIndex && !theEndFlag)
			thePoint = inStart + inCount;	/* theBeginIndex == mNumberOfEntries の場合を含む  */
		else
			thePoint = psRef->entries[theBeginIndex*2];
		result = MDPointSetInsertAnEntry(psRef, theBeginIndex, inStart, thePoint);
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
			return MDPointSetDeleteEntries(psRef, theEndIndex, theEndIndex);
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
				return MDPointSetDeleteEntries(psRef, theIndex, theIndex);
			else {
				psRef->entries[theIndex*2] = psRef->entries[theIndex*2+1];
				psRef->entries[theIndex*2+1] = inStart + inCount;
			}
		}
	}
	return 0;
}

/* --------------------------------------
 ･ MDPointSetAddPointSet
 -------------------------------------- */
MDStatus
MDPointSetAddPointSet(MDPointSet *psRef1, const MDPointSet *psRef2)
{
	int i, n1, n2, result;
	if (psRef1 == NULL || psRef2 == NULL)
		return 0;
	for (i = 0; (n1 = MDPointSetGetStartPoint(psRef2, i)) >= 0; i++) {
		n2 = MDPointSetGetInterval(psRef2, i);
		if ((result = MDPointSetAdd(psRef1, n1, n2)) != 0)
			return result;
	}
	return 0;
}

/* --------------------------------------
 ･ MDPointSetRemovePointSet
 -------------------------------------- */
MDStatus
MDPointSetRemovePointSet(MDPointSet *psRef1, const MDPointSet *psRef2)
{
	int i, n1, n2, result;
	if (psRef1 == NULL || psRef2 == NULL)
		return 0;
	for (i = 0; (n1 = MDPointSetGetStartPoint(psRef2, i)) >= 0; i++) {
		n2 = MDPointSetGetInterval(psRef2, i);
		if ((result = MDPointSetRemove(psRef1, n1, n2)) != 0)
			return result;
	}
	return 0;
}

/* --------------------------------------
 ･ MDPointSetReversePointSet
 -------------------------------------- */
MDStatus
MDPointSetReversePointSet(MDPointSet *psRef1, const MDPointSet *psRef2)
{
	int i, n1, n2, result;
	if (psRef1 == NULL || psRef2 == NULL)
		return 0;
	for (i = 0; (n1 = MDPointSetGetStartPoint(psRef2, i)) >= 0; i++) {
		n2 = MDPointSetGetInterval(psRef2, i);
		if ((result = MDPointSetReverse(psRef1, n1, n2)) != 0)
			return result;
	}
	return 0;
}

/* --------------------------------------
	･ MDPointSetGetStartPoint
   -------------------------------------- */
long
MDPointSetGetStartPoint(const MDPointSet *psRef, long inIndex)
{
	if (psRef == NULL || inIndex < 0 || inIndex >= psRef->num)
		return -1;
	else return psRef->entries[inIndex*2];
}

/* --------------------------------------
	･ MDPointSetGetEndPoint
   -------------------------------------- */
long
MDPointSetGetEndPoint(const MDPointSet *psRef, long inIndex)
{
	if (psRef == NULL || inIndex < 0 || inIndex >= psRef->num)
		return -1;
	else return psRef->entries[inIndex*2+1];
}

/* --------------------------------------
	･ MDPointSetGetInterval
   -------------------------------------- */
long
MDPointSetGetInterval(const MDPointSet *psRef, long inIndex)
{
	if (psRef == NULL || inIndex < 0 || inIndex >= psRef->num)
		return -1;
	else return psRef->entries[inIndex*2+1] - psRef->entries[inIndex*2];
}

/* --------------------------------------
	･ MDPointSetGetNthPoint
   -------------------------------------- */
long
MDPointSetGetNthPoint(const MDPointSet *psRef, long inCount)
{
	long i, n, dn;
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
	･ MDPointSetMinimum
   -------------------------------------- */
long
MDPointSetMinimum(const MDPointSet *psRef)
{
	if (psRef == NULL || psRef->num == 0)
		return -1;
	return psRef->entries[0];
}

/* --------------------------------------
	･ MDPointSetMaximum
   -------------------------------------- */
long
MDPointSetMaximum(const MDPointSet *psRef)
{
	if (psRef == NULL || psRef->num == 0)
		return -1;
	return psRef->entries[psRef->num*2-1] - 1;
}

/* --------------------------------------
	･ MDPointSetOffset
   -------------------------------------- */
MDStatus
MDPointSetOffset(MDPointSet *psRef, int offset)
{
	int i;
	if (psRef == NULL || psRef->num == 0)
		return kMDNoError;
	if (psRef->entries[0] + offset < 0)
		return kMDErrorOutOfRange;  /*  Negative number is not allowed  */
	for (i = 0; i < psRef->num; i++) {
		psRef->entries[i*2] += offset;
		psRef->entries[i*2+1] += offset;
	}
	return kMDNoError;
}

#ifdef __MWERKS__
#pragma mark ====== Binary Operations ======
#endif

/* --------------------------------------
	･ MDPointSetUnion
   -------------------------------------- */
MDStatus
MDPointSetUnion(const MDPointSet *psRef1, const MDPointSet *psRef2, MDPointSet *psRef3)
{
	long i, startPt;
	MDStatus result;
	result = MDPointSetCopy(psRef3, psRef2);
	if (result != kMDNoError)
		return result;
	for (i = 0; i < psRef1->num; i++) {
		startPt = psRef1->entries[i*2];
		result = MDPointSetAdd(psRef3, startPt, psRef1->entries[i*2+1] - startPt);
		if (result != kMDNoError)
			return result;
	}
	return kMDNoError;
}

/* --------------------------------------
	･ MDPointSetIntersect
   -------------------------------------- */
MDStatus
MDPointSetIntersect(const MDPointSet *psRef1, const MDPointSet *psRef2, MDPointSet *psRef3)
{
	return MDPointSetMyIntersect(kMDPointSetIntersect, psRef1, psRef2, psRef3);
}

/* --------------------------------------
	･ MDPointSetXor
   -------------------------------------- */
MDStatus
MDPointSetXor(const MDPointSet *psRef1, const MDPointSet *psRef2, MDPointSet *psRef3)
{
    MDStatus result;
    long i, startPt;
    result = MDPointSetCopy(psRef3, psRef1);
    if (result != kMDNoError)
        return result;
    for (i = 0; i < psRef2->num; i++) {
        startPt = psRef2->entries[i*2];
        result = MDPointSetReverse(psRef3, startPt, psRef2->entries[i*2+1] - startPt);
        if (result != kMDNoError)
            return result;
    }
    return kMDNoError;
}

/* --------------------------------------
	･ MDPointSetConvolute
   -------------------------------------- */
MDStatus
MDPointSetConvolute(const MDPointSet *psRef1, const MDPointSet *psRef2, MDPointSet *psRef3)
{
	return MDPointSetMyIntersect(kMDPointSetConvolute, psRef1, psRef2, psRef3);
}

/* --------------------------------------
	･ MDPointSetDeconvolute
   -------------------------------------- */
MDStatus
MDPointSetDeconvolute(const MDPointSet *psRef1, const MDPointSet *psRef2, MDPointSet *psRef3)
{
	return MDPointSetMyIntersect(kMDPointSetDeconvolute, psRef1, psRef2, psRef3);
}

/* --------------------------------------
	･ MDPointSetNegate
   -------------------------------------- */
MDStatus
MDPointSetNegate(const MDPointSet *psRef1, MDPointSet *psRef2)
{
	long i;

	MDPointSetCopy(psRef2, psRef1);
	if (psRef1->num == 0) {
		//  空集合
		return MDPointSetInsertAnEntry(psRef2, 0, 0, LONG_MAX);
	}
	
	if (psRef1->entries[0] == 0) {
		for (i = 0; i < psRef1->num - 1; i++) {
			psRef2->entries[i*2] = psRef1->entries[i*2+1];
			psRef2->entries[i*2+1] = psRef1->entries[(i+1)*2];
		}
		if (psRef1->entries[i*2+1] != LONG_MAX) {
			psRef2->entries[i*2] = psRef1->entries[i*2+1];
			psRef2->entries[i*2+1] = LONG_MAX;
		} else return MDPointSetDeleteEntries(psRef2, i, i);
	} else {
		psRef2->entries[0] = 0;
		psRef2->entries[1] = psRef1->entries[0];
		for (i = 1; i < psRef1->num; i++) {
			psRef2->entries[i*2] = psRef1->entries[(i-1)*2+1];
			psRef2->entries[i*2+1] = psRef1->entries[i*2];
		}
		if (psRef1->entries[(i-1)*2+1] != LONG_MAX) {
			return MDPointSetInsertAnEntry(psRef2, i, psRef1->entries[(i-1)*2+1], LONG_MAX);
		}
	}
	return kMDNoError;
}

MDStatus
MDPointSetDifference(const MDPointSet *psRef1, const MDPointSet *psRef2, MDPointSet *psRef3)
{
    MDStatus result;
    int i, startPt;
    result = MDPointSetCopy(psRef3, psRef1);
    if (result != kMDNoError)
        return result;
    for (i = 0; i < psRef2->num; i++) {
        startPt = psRef2->entries[i*2];
        result = MDPointSetRemove(psRef3, startPt, psRef2->entries[i*2+1] - startPt);
        if (result != kMDNoError)
            return result;
    }
    return kMDNoError;
}

#ifdef __MWERKS__
#pragma mark ====== Debugging ======
#endif

/* --------------------------------------
	･ MDPointSetDump
   -------------------------------------- */
void
MDPointSetDump(const MDPointSet *pset)
{
    long i, n, m;
    fprintf(stderr, "PointSet[%p]: ", pset);
    for (i = 0; i < pset->num; i++) {
        n = pset->entries[i*2];
        m = pset->entries[i*2+1];
        fprintf(stderr, "%ld", n);
        if (m > n + 1)
            fprintf(stderr, "-%ld", m-1);
        if (i < pset->num - 1)
            fprintf(stderr, ",");
    }
    fprintf(stderr, "\n");
}

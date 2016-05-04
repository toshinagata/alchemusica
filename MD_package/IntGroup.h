/*
 *  IntGroup.h
 *
 *  Created by Toshi Nagata on Sun Jun 17 2001.

   Copyright (c) 2000-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#ifndef __IntGroup_h__
#define __IntGroup_h__

typedef struct IntGroup			IntGroup;
typedef struct IntGroupIterator	IntGroupIterator;

struct IntGroupIterator {
    int			refCount;
    IntGroup *	intGroup;
    int			index;
    int			position;
};

typedef int IntGroupStatus;
enum {
    kIntGroupStatusNoError = 0,
    kIntGroupStatusOutOfMemory,
	kIntGroupStatusOutOfRange
};

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------
    IntGroup functions
   -------------------------------------------------------------------  */

/*  新しい IntGroupRecord をアロケートする。メモリ不足の場合は NULL を返す。 */
IntGroup *	IntGroupNew(void);

/*  Initialize a new IntGroupRecord that has been statically allocated  */
IntGroupIterator *IntGroupIteratorInit(IntGroup *psRef, IntGroupIterator *piRef);

/*  Allocate a new IntGroup, with points specified by arguments
    (start, length, start, length, etc...). Arguments end when start < 0.  */
IntGroup *  IntGroupNewWithPoints(int start, ...);

/*  Duplicate an existing IntGroup  */
IntGroup *IntGroupNewFromIntGroup(const IntGroup *src);

/*  IntGroup の retain/release。 */
void	IntGroupRetain(IntGroup *psRef);
void	IntGroupRelease(IntGroup *psRef);

/*  すべての点を取り除いて空集合にする  */
void	IntGroupClear(IntGroup *psRef);

IntGroupStatus	IntGroupCopy(IntGroup *psRef1, const IntGroup *psRef2);

/*  inStart から始まる inCount 個の点を集合に加える・取り除く・反転する */
IntGroupStatus	IntGroupAdd(IntGroup *psRef, int inStart, int inCount);
IntGroupStatus	IntGroupRemove(IntGroup *psRef, int inStart, int inCount);
IntGroupStatus	IntGroupReverse(IntGroup *psRef, int inStart, int inCount);

IntGroupStatus IntGroupAddIntGroup(IntGroup *psRef1, const IntGroup *psRef2);
IntGroupStatus IntGroupRemoveIntGroup(IntGroup *psRef1, const IntGroup *psRef2);
IntGroupStatus IntGroupReverseIntGroup(IntGroup *psRef1, const IntGroup *psRef2);
	
/*  inPoint なる点が集合に含まれていれば non-zero, 含まれていなければ zero を返す。
    outIndex が NULL でなければ、*outIndex に「何番目の区間」に含まれているかを返す。 */
int			IntGroupLookup(const IntGroup *psRef, int inPoint, int *outIndex);

int     IntGroupIsEqual(const IntGroup *psRef1, const IntGroup *psRef2);

/*  含まれる点の数を返す  */
int		IntGroupGetCount(const IntGroup *psRef);

/*  含まれる区間の数を返す  */
int		IntGroupGetIntervalCount(const IntGroup *psRef);

/*  inIndex 番目（０からスタート）の区間の開始点を返す。inIndex 番目の区間が
    存在しなければ -1 を返す。 */
int		IntGroupGetStartPoint(const IntGroup *psRef, int inIndex);

/*  inIndex 番目（０からスタート）の区間の終了点を返す（この点自身は区間には含まれない）。
    inIndex 番目の区間が存在しなければ -1 を返す。 */
int		IntGroupGetEndPoint(const IntGroup *psRef, int inIndex);

/*  inIndex 番目（０からスタート）の区間の長さを返す。inIndex 番目の区間が
    存在しなければ -1 を返す。 */
int		IntGroupGetInterval(const IntGroup *psRef, int inIndex);

/*  inCount 番目の点を返す。そのような点が存在しなければ -1 を返す。 */
int	IntGroupGetNthPoint(const IntGroup *psRef, int inCount);

/*  inPoint なる点が存在するなら、先頭から何番目になるかを返す。存在しなければ-1を返す。 */
int IntGroupLookupPoint(const IntGroup *psRef, int inPoint);

/*  ２項演算  */
IntGroupStatus	IntGroupUnion(const IntGroup *psRef1, const IntGroup *psRef2, IntGroup *psRef3);
IntGroupStatus	IntGroupIntersect(const IntGroup *psRef1, const IntGroup *psRef2, IntGroup *psRef3);
IntGroupStatus	IntGroupXor(const IntGroup *psRef1, const IntGroup *psRef2, IntGroup *psRef3);
IntGroupStatus	IntGroupConvolute(const IntGroup *psRef1, const IntGroup *psRef2, IntGroup *psRef3);
IntGroupStatus	IntGroupDeconvolute(const IntGroup *psRef1, const IntGroup *psRef2, IntGroup *psRef3);
IntGroupStatus	IntGroupDifference(const IntGroup *psRef1, const IntGroup *psRef2, IntGroup *psRef3);

/*  反転  */
IntGroupStatus	IntGroupNegate(const IntGroup *psRef1, IntGroup *psRef2);

/*  Add offset to all points  */
IntGroupStatus  IntGroupOffset(IntGroup *psRef, int offset);

/*  Minimum and maximum number included in this group  */
int IntGroupMinimum(const IntGroup *psRef);
int IntGroupMaximum(const IntGroup *psRef);

/*  Debug  */
char *IntGroupInspect(const IntGroup *pset);
void		IntGroupDump(const IntGroup *pset);

/*  Iterator support  */
IntGroupIterator *IntGroupIteratorNew(IntGroup *psRef);
IntGroupIterator *IntGroupIteratorInit(IntGroup *psRef, IntGroupIterator *piRef);
void IntGroupIteratorRetain(IntGroupIterator *piRef);
void IntGroupIteratorRelease(IntGroupIterator *piRef);
void IntGroupIteratorReset(IntGroupIterator *piRef);
void IntGroupIteratorResetAtLast(IntGroupIterator *piRef);
int IntGroupIteratorNext(IntGroupIterator *piRef);
int IntGroupIteratorLast(IntGroupIterator *piRef);

#ifdef __cplusplus
}
#endif

#endif  /*  __IntGroup_h__  */

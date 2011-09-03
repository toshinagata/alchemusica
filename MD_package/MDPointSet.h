/*
 *  MDPointSet.h
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

#ifndef __MDPointSet__
#define __MDPointSet__

/*  非負整数値の集合を表す構造体。 */
typedef struct MDPointSet			MDPointSet;

#ifndef __MDCommon__
#include "MDCommon.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------
    MDPointSet functions
   -------------------------------------------------------------------  */

/*  新しい MDPointSetRecord をアロケートする。メモリ不足の場合は NULL を返す。 */
MDPointSet *	MDPointSetNew(void);

/*  MDPointSet の retain/release。 */
void	MDPointSetRetain(MDPointSet *psRef);
void	MDPointSetRelease(MDPointSet *psRef);

/*  すべての点を取り除いて空集合にする  */
void	MDPointSetClear(MDPointSet *psRef);

MDStatus	MDPointSetCopy(MDPointSet *psRef1, const MDPointSet *psRef2);

/*  inStart から始まる inCount 個の点を集合に加える・取り除く・反転する */
MDStatus	MDPointSetAdd(MDPointSet *psRef, long inStart, long inCount);
MDStatus	MDPointSetRemove(MDPointSet *psRef, long inStart, long inCount);
MDStatus	MDPointSetReverse(MDPointSet *psRef, long inStart, long inCount);

MDStatus	MDPointSetAddPointSet(MDPointSet *psRef1, const MDPointSet *psRef2);
MDStatus	MDPointSetRemovePointSet(MDPointSet *psRef1, const MDPointSet *psRef2);
MDStatus	MDPointSetReversePointSet(MDPointSet *psRef1, const MDPointSet *psRef2);

/*  inPoint なる点が集合に含まれていれば non-zero, 含まれていなければ zero を返す。
    outIndex が NULL でなければ、*outIndex に「何番目の区間」に含まれているかを返す。 */
int			MDPointSetLookup(const MDPointSet *psRef, long inPoint, long *outIndex);

/*  含まれる点の数を返す  */
long		MDPointSetGetCount(const MDPointSet *psRef);

/*  含まれる区間の数を返す  */
long		MDPointSetGetIntervalCount(const MDPointSet *psRef);

/*  inIndex 番目（０からスタート）の区間の開始点を返す。inIndex 番目の区間が
    存在しなければ -1 を返す。 */
long		MDPointSetGetStartPoint(const MDPointSet *psRef, long inIndex);

/*  inIndex 番目（０からスタート）の区間の終了点を返す（この点自身は区間には含まれない）。
    inIndex 番目の区間が存在しなければ -1 を返す。 */
long		MDPointSetGetEndPoint(const MDPointSet *psRef, long inIndex);

/*  inIndex 番目（０からスタート）の区間の長さを返す。inIndex 番目の区間が
    存在しなければ -1 を返す。 */
long		MDPointSetGetInterval(const MDPointSet *psRef, long inIndex);

long		MDPointSetGetNthPoint(const MDPointSet *psRef, long inCount);
MDStatus	MDPointSetOffset(MDPointSet *psRef, int offset);


/*  Minimum and maximum number included in this point set  */
long        MDPointSetMinimum(const MDPointSet *psRef);
long        MDPointSetMaximum(const MDPointSet *psRef);

/*  ２項演算  */
MDStatus	MDPointSetUnion(const MDPointSet *psRef1, const MDPointSet *psRef2, MDPointSet *psRef3);
MDStatus	MDPointSetIntersect(const MDPointSet *psRef1, const MDPointSet *psRef2, MDPointSet *psRef3);
MDStatus	MDPointSetXor(const MDPointSet *psRef1, const MDPointSet *psRef2, MDPointSet *psRef3);
MDStatus	MDPointSetConvolute(const MDPointSet *psRef1, const MDPointSet *psRef2, MDPointSet *psRef3);
MDStatus	MDPointSetDeconvolute(const MDPointSet *psRef1, const MDPointSet *psRef2, MDPointSet *psRef3);
MDStatus	MDPointSetDifference(const MDPointSet *psRef1, const MDPointSet *psRef2, MDPointSet *psRef3);

/*  反転  */
MDStatus	MDPointSetNegate(const MDPointSet *psRef1, MDPointSet *psRef2);

/*  Debug  */
void		MDPointSetDump(const MDPointSet *pset);

#ifdef __cplusplus
}
#endif

#endif  /*  __MDPointSet__  */

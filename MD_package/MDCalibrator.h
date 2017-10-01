/*
 *  MDCalibrator.h
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

#ifndef __MDCalibrator__
#define __MDCalibrator__

/*
    MDCalibrator は、メタイベントが持っている情報をキャッシュしておき「現在位置」での情報を
	すばやく取りだせるようにする。
	tempo, time signature については内部データ（それぞれそのイベント位置での絶対時間、小節番号）
	を同時に管理する。それ以外のイベントについては data1 フィールドだけを管理する。data1 以外のフィールド
	が意味をもつイベント（テキスト系メタイベントなど）の場合はイベントへのポインタそのものを取り出して利用できる。 */

typedef struct MDCalibrator MDCalibrator;

#ifndef __MDCommon__
#include "MDCommon.h"
#endif

#ifndef __MDSequence__
#include "MDSequence.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------
    MDCalibrator functions
   -------------------------------------------------------------------  */
/*  inKind が kMDEventTempo または kMDEventTimeSignature のときは、inTrack は　NULL でよい。
    （自動的にコンダクタートラックが使われる） 
	inCode は code でイベント種類が指定される（できる）以下のイベントについて指定する： 
	kMDEventMeta, kMDEventMetaText, kMDEventMetaMessage, kMDEventNoteOff, kMDEventNoteOn,
	kMDEventNote, kMDEventControl, kMDEventKeyPres, kMDEventData, kMDEventObject.
	code を問わずどのイベントも認識させるためには inCode に -1 を渡す。
*/
MDCalibrator *	MDCalibratorNew(MDSequence *inSequence, MDTrack *inTrack, MDEventKind inKind, short inCode);
void			MDCalibratorRetain(MDCalibrator *inCalib);
void			MDCalibratorRelease(MDCalibrator *inCalib);

/*  MDCalibrator は１つのインスタンスについて複数の情報を管理できる（実際には複数のレコードを
    リストにしてつないでいるだけ）。 */
MDStatus		MDCalibratorAppend(MDCalibrator *inCalib, MDTrack *inTrack, MDEventKind inKind, short inCode);

/*  MDCalibrator の index 番目のレコードが管理している情報を得る。index が不正な値の場合は kMDErrorBadParameter を返す。  */
MDStatus		MDCalibratorGetInfo(MDCalibrator *inCalib, int index, MDTrack **outTrack, MDEventKind *outKind, short *outCode);

/*  MDCalibrator の index 番目のレコードを破棄する。 */
MDStatus		MDCalibratorRemoveAtIndex(MDCalibrator *inCalib, int index);

/*  inCalib がある track/kind/code の情報を管理しているか  */
int             MDCalibratorIsSupporting(MDCalibrator *inCalib, MDTrack *inTrack, MDEventKind inKind, short inCode);

/*  リセット。内部にキャッシュされている情報を破棄する  */
void			MDCalibratorReset(MDCalibrator *inCalib);

/*  inCalib->next (inCalib->chain ではなく) を返す。内部的にのみ使われる。  */
MDCalibrator *	MDCalibratorNextInList(MDCalibrator *inCalib);
void			MDCalibratorSetNextInList(MDCalibrator *inCalib, MDCalibrator *inNextCalib);

/*  inTick の位置に移動する  */
void			MDCalibratorJumpToTick(MDCalibrator *inCalib, MDTickType inTick);

/*  指定したトラックの inPosition の位置に移動する。指定トラック以外の情報については、そのイベントの tick 位置に移動する  */
void            MDCalibratorJumpToPositionInTrack(MDCalibrator *inCalib, int32_t inPosition, MDTrack *inTrack);

/*  小節・拍・カウント表記 <-> tick 変換  */
MDTickType		MDCalibratorMeasureToTick(MDCalibrator *inCalib, int32_t inMeasure, int32_t inBeat, int32_t inTick);
void			MDCalibratorTickToMeasure(MDCalibrator *inCalib, MDTickType inTick, int32_t *outMeasure, int32_t *outBeat, int32_t *outTick);

float			MDCalibratorGetTempo(MDCalibrator *inCalib);
MDTickType		MDCalibratorTimeToTick(MDCalibrator *inCalib, MDTimeType inTime);
MDTimeType		MDCalibratorTickToTime(MDCalibrator *inCalib, MDTickType inTick);

MDEvent *		MDCalibratorGetEvent(MDCalibrator *inCalib, MDTrack *inTrack, MDEventKind inKind, short inCode);
MDEvent *		MDCalibratorGetNextEvent(MDCalibrator *inCalib, MDTrack *inTrack, MDEventKind inKind, short inCode);
int32_t			MDCalibratorGetEventPosition(MDCalibrator *inCalib, MDTrack *inTrack, MDEventKind inKind, short inCode);
MDPointer *		MDCalibratorCopyPointer(MDCalibrator *inCalib, MDTrack *inTrack, MDEventKind inKind, short inCode);

#ifdef __cplusplus
}
#endif

#endif  /*  __MDCalibrator__  */

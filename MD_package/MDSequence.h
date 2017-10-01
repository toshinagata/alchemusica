/*
 *  MDSequence.h
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

#ifndef __MDSequence__
#define __MDSequence__

/*  シーケンスをあらわす構造体。シーケンスは、コンダクタートラックと MIDI トラック
    （複数可）から成る。 */
typedef struct MDSequence		MDSequence;

/*  シーケンス中の全トラック中の全イベントをティック順に取り出すための仕掛け。 */
/* typedef struct MDMerger			MDMerger; */

/*  コピー／ペースト実装のための内部データ  */
typedef struct MDCatalogTrack {
	int originalTrackNo;
	char name[64];
	int numEvents;
	int numMIDIEvents;
} MDCatalogTrack;

typedef struct MDCatalog {
	int num;       /*  Number of tracks  */
	MDTickType startTick, endTick;  /*  Editing range  */
	MDCatalogTrack catTrack[1];
} MDCatalog;
	
#ifndef __MDTrack__
#include "MDTrack.h"
#endif

#ifndef __MDCalibrator__
#include "MDCalibrator.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------
    MDSequence functions
   -------------------------------------------------------------------  */

/*  新しい MDSequenceRecord をアロケートする。メモリ不足の場合は NULL を返す。 
    MDTrackNew() に対応する dispose や delete 関数は無い。代わりに MDTrackRelease() 
    を使用すること。 */
MDSequence *	MDSequenceNew(void);

/*  MDSequence の retain/release。 */
void	MDSequenceRetain(MDSequence *inSequence);
void	MDSequenceRelease(MDSequence *inSequence);

/*  MDTrack に含まれているトラックをすべてクリアする。 */
void	MDSequenceClear(MDSequence *inSequence);

/*  タイムベースを変更する。（イベントの内部データは変更されない） */
void	MDSequenceSetTimebase(MDSequence *inSequence, int32_t inTimebase);

/*  タイムベースを得る。 */
int32_t	MDSequenceGetTimebase(const MDSequence *inSequence);

/*  含まれているトラックの数を返す（コンダクタートラックを含む）。 */
int32_t	MDSequenceGetNumberOfTracks(const MDSequence *inSequence);

/*  シーケンスの長さ（tick 単位）を返す。 */
MDTickType	MDSequenceGetDuration(const MDSequence *inSequence);

/*  index 番目のトラック（先頭＝コンダクタートラックが０）を返す */
MDTrack *	MDSequenceGetTrack(const MDSequence *inSequence, int32_t index);

/*  index 番目にトラックを挿入する。index が大きすぎるかまたは -1 の場合にはトラック
    リストの末尾に挿入する。実際に挿入した位置を返す。 */
int32_t	MDSequenceInsertTrack(MDSequence *inSequence, int32_t index, MDTrack *inTrack);

/*  index 番目のトラックを削除する。削除されたトラックは MDTrackRelease() される。
    実際に挿入したトラックの番号を返す。 */
int32_t	MDSequenceDeleteTrack(MDSequence *inSequence, int32_t index);

/*  index 番目のトラックを新しいトラックで置き換える。置き換えられたトラックは
    MDTrackRelease() される。index が大きすぎる場合には何もせず -1 を返す。 */
int32_t	MDSequenceReplaceTrack(MDSequence *inSequence, int32_t index, MDTrack *inTrack);

/*  index 番目のトラックの Record フラグをセットする。flag = 0: OFF, 1: ON, -1: toggle。Record フラグが変更された場合は non-zero, 変更されなかった場合は 0 を返す。
    トラックの Record フラグが新たにセットされた場合は、他のトラックの Record フラグは自動的にリセットされる。 */
int		MDSequenceSetRecordFlagOnTrack(MDSequence *inSequence, int32_t index, int flag);

/*  index 番目のトラックの Solo フラグをセットする。flag = 0: OFF, 1: ON, -1: toggle
    この他のトラックの MuteBySolo フラグも更新される。  */
int		MDSequenceSetSoloFlagOnTrack(MDSequence *inSequence, int32_t index, int flag);

/*  index 番目のトラックの Mute フラグをセットする。flag = 0: OFF, 1: ON, -1: toggle  */
int		MDSequenceSetMuteFlagOnTrack(MDSequence *inSequence, int32_t index, int flag);

/*  MuteBySolo フラグを更新する。Solo フラグを変更したあと呼び出す。  */
void	MDSequenceUpdateMuteBySoloFlag(MDSequence *inSequence);

/*  Record フラグが立っているトラックの番号を得る。なければ -1 を返す。  */
int32_t	MDSequenceGetIndexOfRecordingTrack(MDSequence *inSequence);

/*  Single channel mode に移行する。Single channel mode では、すべての MIDI イベントのチャンネルは０になり、実際に MIDI チャンネルが必要な時（MIDI入出力時、およびSMFのインポート／エキスポート時）にはトラックチャンネルの値が使われる。 */
/* separate が non-zero ならば、すべてのトラックの内容がチェックされ、複数のチャンネルにまたがっているトラックはチャンネルごとに分割される。各トラックごとのMIDIチャンネルが一つになったあと、その値がトラックチャンネルがセットされ、MIDIイベントのチャンネルの値は０になる。 */
MDStatus	MDSequenceSingleChannelMode(MDSequence *inSequence, int separate);

/*  Multi channel mode に移行する。MIDIイベントのchannelフィールドにトラックチャンネルの値をセットする。デフォルトは multi channel mode。 */
MDStatus	MDSequenceMultiChannelMode(MDSequence *inSequence);

/*  Single channel mode なら non-zero, multi channel mode なら 0 を返す。 */
int			MDSequenceIsSingleChannelMode(const MDSequence *inSequence);

/*  MDSequenceReadSMF(), MDSequenceWriteSMF() で使うコールバック。処理の進行度 (0.0-1.0) と任意のポインタを渡し、
	通常は 1, ユーザーがキャンセルを要求したら 0 を返す。 */
typedef int	(*MDSequenceCallback)(float, void *);

/*  ファイル（ストリーム）から SMF を読み込む。読み込みに失敗したらエラーコードを返す。
    この時 MDSequence の内容は空になる。 */
MDStatus	MDSequenceReadSMF(MDSequence *inSequence, STREAM stream, MDSequenceCallback callback, void *cbdata);

/*  ファイル（ストリーム）に SMF を書き出す。途中で失敗したら中断してエラーコードを返す。 */
MDStatus	MDSequenceWriteSMF(MDSequence *inSequence, STREAM stream, MDSequenceCallback callback, void *cbdata);

/*  ファイル（ストリーム）に選択されたイベントを SMF として書き出す。i 番目のトラックの選択は psetArray[i] で指示され、これが NULL ならそのトラックはスキップ、有効な IntGroup ならそれが指定するイベントを書き出し、(IntGroup *)(-1) ならそのトラック中のすべてのイベントを書き出す。IntGroup を指定したときは、end-of-track を選択しているかどうかを eotSelectFlags[i] で指示することができる。 */
MDStatus	MDSequenceWriteSMFWithSelection(MDSequence *inSequence, IntGroup **psetArray, char *eotSelectFlags, STREAM stream, MDSequenceCallback callback, void *cbdata);

/*  ストリームに MDCatalog を書き出す。 */
MDStatus    MDSequenceWriteCatalog(MDCatalog *inCatalog, STREAM stream);

/*  ストリームから MDCatalog の内容を読み出し、新たに malloc した MDCatalog に格納して返す。 */
MDCatalog  *MDSequenceReadCatalog(STREAM stream);

/*  MDCalibrator をアタッチ・デタッチする  */
void		MDSequenceAttachCalibrator(MDSequence *inSequence, MDCalibrator *inCalib);
void		MDSequenceDetachCalibrator(MDSequence *inSequence, MDCalibrator *inCalib);

/*  MDCalibrator をすべてリセットする。 */
void		MDSequenceResetCalibrators(MDSequence *inSequence);

/*  Lock/Unlock MDSequence (for multithread application)  */
MDStatus	MDSequenceCreateMutex(MDSequence *inSequence);
MDStatus	MDSequenceDisposeMutex(MDSequence *inSequence);
void		MDSequenceLock(MDSequence *inSequence);
void		MDSequenceUnlock(MDSequence *inSequence);
int			MDSequenceTryLock(MDSequence *inSequence);

#if 0
/* -------------------------------------------------------------------
    MDMerger functions
   -------------------------------------------------------------------  */

/*  新しい MDMerger をアロケートする。メモリ不足の場合は NULL を返す。 */
MDMerger *		MDMergerNew(MDSequence *inSequence);

/*  Retain/release  */
void			MDMergerRetain(MDMerger *inMerger);
void			MDMergerRelease(MDMerger *inMerger);

/*  新しい MDMerger をアロケートし、その内容を inSrc と同じにする  */
MDMerger *		MDMergerDuplicate(const MDMerger *inSrc);

/*  MDSequence との関係付けを変更する。 */
MDStatus		MDMergerSetSequence(MDMerger *inMerger, MDSequence *inSequence);

/*  関係付けられた MDSequence を返す。 */
MDSequence *	MDMergerGetSequence(MDMerger *inMerger);

/*  内部情報を完全に更新する。 */
void			MDMergerReset(MDMerger *inMerger);

/*  inTick より小さくない tick 値を持つ最初のイベントの位置に移動する。そのような
    イベントが存在しなければ末尾以降に移動し、0 (false) を返す。 */
int				MDMergerJumpToTick(MDMerger *inMerger, MDTickType inTick);

/*  現在のイベントへのポインタを得る。存在しないイベントを指している場合は NULL を返す。 */
MDEvent *		MDMergerCurrent(const MDMerger *inMerger);

/*  １つ先の位置に進み、そのイベントへのポインタを得る。最後のイベントを越えた場合は
    NULL を返す。 */
MDEvent *		MDMergerForward(MDMerger *inMerger);

/*  １つ前の位置に戻り、そのイベントへのポインタを得る。先頭のイベントを越えた場合は
    NULL を返す。 */
MDEvent *		MDMergerBackward(MDMerger *inMerger);

/*  現在のイベントが属するトラック番号を得る。 */
int32_t			MDMergerGetCurrentTrack(MDMerger *inMerger);

/*  現在のイベントのトラック内での位置（番号）を得る。  */
int32_t			MDMergerGetCurrentPositionInTrack(MDMerger *inMerger);

/*  現在のイベントのティックを得る。  */
MDTickType		MDMergerGetTick(MDMerger *inMerger);

#endif

#ifdef __cplusplus
}
#endif

#endif  /*  __MDSequence__  */

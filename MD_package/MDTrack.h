/*
 *  MDTrack.h
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

#ifndef __MDTrack__
#define __MDTrack__

/*  MIDI イベントの列を格納する構造体  */
typedef struct MDTrack			MDTrack;

/*  MDTrack 中のイベントの位置を指定する構造体。MDTrack と
    連動して働き、イベントの挿入・削除が行われると自動的に指す位置が変化する。
    MDPointer は opaque ではなく、ポインタだけでなくそれ自体を使うことができる。
    （ただし、フィールドにアクセスすることはできない） */
typedef struct MDPointer			MDPointer;

/*  シーケンス中の全トラック中の全イベントをティック順に取り出すための仕掛け。 */
/*  MDSequence.h の MDMerger と違って、MDSequence には依存しない。 */
typedef struct MDTrackMerger		MDTrackMerger;

typedef unsigned char MDTrackAttribute;
enum {
    kMDTrackAttributeRecord = 1,
    kMDTrackAttributeSolo = 2,
    kMDTrackAttributeMute = 4,
    kMDTrackAttributeMuteBySolo = 8, /* Solo トラックが１つ以上ある時、それ以外のトラックはすべてこのフラグが立つ  */
	kMDTrackAttributeHidden = 16,
	kMDTrackAttributeEditable = 32
};

#ifndef __MDEvent__
#include "MDEvent.h"
#endif

#ifndef __IntGroup_h__
#include "IntGroup.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/*  MDPointerForwardWithSelector(), MDPointerBackwardWithSelector() などで使う
    コールバック関数 */
typedef int	(*MDEventSelector)(const MDEvent *ep, int32_t position, void *inUserData);

/* -------------------------------------------------------------------
    MDTrack functions
   -------------------------------------------------------------------  */

/*  新しい MDTrackRecord をアロケートする。メモリ不足の場合は NULL を返す。 
    MDTrackNew() に対応する dispose や delete 関数は無い。代わりに MDTrackRelease() 
    を使用すること。 */
MDTrack *	MDTrackNew(void);

/*  新しい MDTrack を作成し、そこに inTrack の全イベントをコピーする。 */
MDTrack *	MDTrackNewFromTrack(const MDTrack *inTrack);

/*  MDTrack の retain/release。 */
void	MDTrackRetain(MDTrack *inTrack);
void	MDTrackRelease(MDTrack *inTrack);

/*  MDTrack に含まれているイベントをすべてクリアする。 */
void	MDTrackClear(MDTrack *inTrack);

void	MDTrackExchange(MDTrack *inTrack1, MDTrack *inTrack2);

/*  含まれているイベントの数を返す。 */
int32_t	MDTrackGetNumberOfEvents(const MDTrack *inTrack);

/*  含まれているチャンネルイベントの数を返す。channel が 0-15 の範囲でなければ
    すべてのチャンネルイベントの数の合計を返す。 */
int32_t	MDTrackGetNumberOfChannelEvents(const MDTrack *inTrack, short channel);

/*  含まれているシステムエクスクルーシブイベントの数を返す。 */
int32_t	MDTrackGetNumberOfSysexEvents(const MDTrack *inTrack);

/*  含まれている non-MIDI イベント(メタイベント)の数を返す。 */
int32_t	MDTrackGetNumberOfNonMIDIEvents(const MDTrack *inTrack);

/*  シーケンスの長さを返す。 */
MDTickType	MDTrackGetDuration(const MDTrack *inTrack);

/*  シーケンスの長さを変更する。既存のイベントの tick との整合性はチェックしないので注意。 */
void	MDTrackSetDuration(MDTrack *inTrack, MDTickType inDuration);

/*  シーケンスの末尾にイベントを追加する。イベントの順序はチェックしないので注意。
    実際に追加できたイベントの数を返す。 */
int32_t	MDTrackAppendEvents(MDTrack *inTrack, const MDEvent *inEvent, int32_t count);

/*  ２つのトラックをマージする（inTrack1 の中に inTrack2 のイベントを挿入する）。
    ioSet は NULL ならば無視される。ioSet != NULL で *ioSet == NULL なら、新しく IntGroup を
    アロケートして、マージ後のトラックで inTrack2 由来のイベントが存在する位置の集合を入れて返す。
	ioSet != NULL で *ioSet != NULL なら、*ioSet がマージ後のトラックで inTrack2 由来のイ
	ベントが存在する位置の集合になるものと見なして挿入位置を決める（実際には、同ティックのイベントの
	順序をどちらにするか、という場合にのみ参照される）。処理終了後には、*ioSet == NULL の
	場合と同じく新しくアロケートされた IntGroup が返される。もとの *ioSet は release されない。 */
MDStatus	MDTrackMerge(MDTrack *inTrack1, const MDTrack *inTrack2, IntGroup **ioSet);

/*  MDTrackMerge の逆操作。inTrack の中から、位置が inSet に含まれるイベントをすべて抜き出して
    新しいトラックに入れ、*outTrack に入れて返す。outTrack が NULL なら抜き出されたイベントは捨てられる。 */
MDStatus	MDTrackUnmerge(MDTrack *inTrack, MDTrack **outTrack, const IntGroup *inSet);

MDStatus	MDTrackExtract(MDTrack *inTrack, MDTrack **outTrack, const IntGroup *inSet);

/*  inTrack を MIDI チャンネルで分けて最大16個のトラックにする。最も若い番号の MIDI チャンネルイベントと、チャンネルイベント以外のイベント（Sysex とメタイベント）は inTrack に残る。outTracks は MDTrack * を 16 個格納できる配列であること。対応するチャンネルイベントがない outTracks の要素は NULL になる。NULL でない最初の要素は inTrack に等しい。NULL でない outTracks の要素数を返す。 */
int         MDTrackSplitByMIDIChannel(MDTrack *inTrack, MDTrack **outTracks);

/*  noteOffEvent に対応する inTrack 中の internal note-on を探し、duration をセットして正常な Note イベントにする。Internal note-on は inTrack の末尾から先頭に向かって検索される。もし internal note-on の duration がゼロでなければ、noteOffevent とそのイベントの tick 差が duration に等しいかどうかもチェックされる。これは重なったノートを正しく対応づけるための処理。 */
MDStatus	MDTrackMatchNoteOff(MDTrack *inTrack, const MDEvent *noteOffEvent);

/*  inTrack のノートイベントで、internal note-on に対応する internal note-off イベントを noteOffTrack から探し出して、duration をセットする。対応がとれた internal note-off イベントは null イベントに変換される（二度読みを防ぐため）。SMF の読み込み、および MIDI レコーディングの時に使う。  */
MDStatus	MDTrackMatchNoteOffInTrack(MDTrack *inTrack, MDTrack *noteOffTrack);

/*  inTrack 中の全イベントの tick を newTick[] 中の値に先頭から順に変更する。newTick[] < 0 なら、そのイベントの tick は変更されない。tick が昇順になっていなければエラーになる。必要に応じて inTrack->duration は変更される。 */
MDStatus    MDTrackChangeTick(MDTrack *inTrack, MDTickType *newTick);

/*  inTrack 中の全イベントの tick に offset を加える。tick + offset が負の場合は 0 になる。必要に応じて inTrack->duration は変更される。 */
MDStatus    MDTrackOffsetTick(MDTrack *inTrack, MDTickType offset);

/*  トラック中で最も大きな tick を返す。duration を持っているイベントがある時は、そのイベントの終了 tick も考慮される。 */
MDTickType  MDTrackGetLargestTick(MDTrack *inTrack);

/*  duration を持っているイベントで、tick < inTick かつ tick+duration >= inTick であるものを 
    探し、その position を IntGroup として返す。メモリ不足の場合は NULL、該当するイベントが 
    １つもないときは空の IntGroup を返す。 */
IntGroup *MDTrackSearchEventsWithDurationCrossingTick(MDTrack *inTrack, MDTickType inTick);

/*  inSelector が non-zero を返すイベントを探し、その position を IntGroup として返す。
    メモリ不足の場合は NULL、該当するイベントが１つもないときは空の IntGroup を返す。 */
IntGroup *MDTrackSearchEventsWithSelector(MDTrack *inTrack, MDEventSelector inSelector, void *inUserData);

/*  MIDIチャンネルを置き換える。チャンネルchのイベントはチャンネルnewch[ch]に変更される。変更先のチャンネルが重複していてもチェックされず、そのまま置換が行われる。newch[ch]が15より大きい時は16で割った余りが新しいチャンネルになる。この関数は必ず成功するので、エラーを発生しない。 */
void		MDTrackRemapChannel(MDTrack *inTrack, const unsigned char *newch);

/*  デバイス番号をセットする。 */
void		MDTrackSetDevice(MDTrack *inTrack, int32_t dev);

/*  デバイス番号を得る。 */
int32_t		MDTrackGetDevice(const MDTrack *inTrack);

/*  トラックのチャンネルをセットする。この値は親シーケンスがシングルチャンネルモードの場合のみ使われる。 */
void		MDTrackSetTrackChannel(MDTrack *inTrack, short ch);

/*  トラックのチャンネルを得る。 */
short		MDTrackGetTrackChannel(const MDTrack *inTrack);

/*  トラックの名前をセットする。文字列 (inName) は malloc でコピーされる。 */
MDStatus	MDTrackSetName(MDTrack *inTrack, const char *inName);

/*  トラックの名前を得る。 */
void		MDTrackGetName(const MDTrack *inTrack, char *outName, int32_t length);

/*  出力デバイスの名前をセットする。文字列 (inName) は malloc でコピーされる。 */
MDStatus	MDTrackSetDeviceName(MDTrack *inTrack, const char *inName);

/*  出力デバイスの名前を得る。 */
void		MDTrackGetDeviceName(const MDTrack *inTrack, char *outName, int32_t length);

/*  メタイベントからトラック名を推測する。 */
void		MDTrackGuessName(MDTrack *inTrack, char *outName, int32_t length);

/*  メタイベントからデバイス名を推測する。 */
void		MDTrackGuessDeviceName(MDTrack *inTrack, char *outName, int32_t length);

/*  トラック属性 (Rec/Solo/Mute) の取得、セット  */
MDTrackAttribute	MDTrackGetAttribute(const MDTrack *inTrack);
void		MDTrackSetAttribute(MDTrack *inTrack, MDTrackAttribute inAttribute);

/*  トラックの内容を標準出力にダンプする  */
void		MDTrackDump(const MDTrack *inTrack);

/*  トラックの内容をチェックする（デバッグ用）。メッセージは stderr に出される  */
/* MDStatus	MDTrackCheck(const MDTrack *inTrack); */

/*  Track の内部情報を正しく更新する。check が non-zero ならば、内部情報が矛盾していれば stderr にメッセージを出力する。 */
int		MDTrackRecache(MDTrack *inTrack, int check);

/* -------------------------------------------------------------------
    MDPointer functions
   -------------------------------------------------------------------  */

/*  新しい MDPointer をアロケートする。メモリ不足の場合は NULL を返す。
    inTrack と関係づけられ、場所は -1 （先頭イベントの前）にセットされる。 */
MDPointer *	MDPointerNew(MDTrack *inTrack);

/*  すでにアロケートされた MDPointer を初期化する。これはローカル変数などで
    確保した MDPointerRecord を利用する時に使う。 */
/* MDPointer *	MDPointerInit(MDPointer *inPointer, const MDTrack *inTrack); */

/*  Retain/release */
void			MDPointerRetain(MDPointer *inPointer);
void			MDPointerRelease(MDPointer *inPointer);

/*  MDPointer をコピーする。parent が違う時は意味がないが、一応 SetPosition を行う。 */
void			MDPointerCopy(MDPointer *inDest, const MDPointer *inSrc);

/*  MDTrack との関係付けを変更する。 */
void			MDPointerSetTrack(MDPointer *inPointer, MDTrack *inTrack);

/*  関係付けられた MDTrack を返す。 */
MDTrack *		MDPointerGetTrack(const MDPointer *inPointer);

/*  現在位置の変更。存在しない位置に移動しようとした時は先頭以前か末尾以降に
    移動し、0 (false) を返す。 */
int				MDPointerSetPosition(MDPointer *inPointer, int32_t inPos);
int				MDPointerSetRelativePosition(MDPointer *inPointer, int32_t inOffset);

/*  現在位置を読み出す */
int32_t			MDPointerGetPosition(const MDPointer *inPointer);

/*  挿入・削除後に位置を自動調整する場合に 1 をセットする。デフォルトは 0  */
void			MDPointerSetAutoAdjust(MDPointer *inPointer, char flag);

/*  自動調整フラグが立っていれば 1, 立っていなければ 0 を返す  */
int				MDPointerIsAutoAdjust(const MDPointer *inPointer);

/*  以前に指していたイベントが削除された結果現在位置を指している場合に 1 (true) を返す */
int				MDPointerIsRemoved(const MDPointer *inPointer);

/*  inTick より小さくない tick 値を持つ最初のイベントの位置に移動する。そのような
    イベントが存在しなければ末尾以降に移動し、0 (false) を返す。 */
int				MDPointerJumpToTick(MDPointer *inPointer, MDTickType inTick);

/*  最後のイベントの位置に移動する。１つもイベントがなければ 0 (false) を返す。 */
int				MDPointerJumpToLast(MDPointer *inPointer);

/*  イベントのポインタが inEvent に一致する位置に移動する。そのようなイベントが存在
    しなければ指している位置は変化せず、 0 (false) を返す。 */
int				MDPointerLookForEvent(MDPointer *inPointer, const MDEvent *inEvent);

/*  現在のイベントへのポインタを得る。存在しないイベントを指している場合は NULL を返す。 */
MDEvent *		MDPointerCurrent(const MDPointer *inPointer);

/*  １つ先の位置に進み、そのイベントへのポインタを得る。最後のイベントを越えた場合は
    NULL を返す。 */
MDEvent *		MDPointerForward(MDPointer *inPointer);

/*  １つ前の位置に戻り、そのイベントへのポインタを得る。先頭のイベントを越えた場合は
    NULL を返す。 */
MDEvent *		MDPointerBackward(MDPointer *inPointer);

/*  現在位置より先で inSelector が non-zero を返す最初のイベントの位置に移動する  */
MDEvent *		MDPointerForwardWithSelector(MDPointer *inPointer, MDEventSelector inSelector, void *inUserData);

/*  現在位置より前で inSelector が non-zero を返す最初のイベントの位置に移動する  */
MDEvent *		MDPointerBackwardWithSelector(MDPointer *inPointer, MDEventSelector inSelector, void *inUserData);

/*  inPointSet 中の offset 番目の点の位置に移動する  */
int				MDPointerSetPositionWithPointSet(MDPointer *inPointer, IntGroup *inPointSet, int32_t offset, int *outIndex);

/*  現在位置より１つ進み、その点が pointSet の *index 番目の区間の終端より先であれば、次の区間の始点に対応する位置に移動して (*index) を +1 する。index == NULL であるか、または *index < 0 であるなら、pointSet に含まれるところまで現在位置を進め、index != NULL ならば *index にその区間の番号を返す。もし対応する点がなければ、inPointer はトラック末尾+1 の位置になり、*index には -1 が返される。 */
MDEvent *		MDPointerForwardWithPointSet(MDPointer *inPointer, IntGroup *inPointSet, int *index);

/*  現在位置から１つ戻り、その点が pointSet の *index 番目の区間の始点より前であれば、前の区間の終点-1に対応する位置に移動して (*index) を -1 する。index == NULL であるか、または *index < 0 であるなら、pointSet に含まれるところまで現在位置を戻し、index != NULL ならば *index にその区間の番号を返す。もし対応する点がなければ、inPointer はトラック先頭-1 の位置になり、*index には -1 が返される。 */
MDEvent *		MDPointerBackwardWithPointSet(MDPointer *inPointer, IntGroup *inPointSet, int *index);

/*  現在位置にイベントを１つ挿入する。tick が現在位置と合わない場合には、合う位置を探す。 */
MDStatus		MDPointerInsertAnEvent(MDPointer *inPointer, const MDEvent *inEvent);

/*  現在位置のイベントを削除する。outEvent が NULL でなければ、古いイベントが *outEvent に返される。*/
MDStatus		MDPointerDeleteAnEvent(MDPointer *inPointer, MDEvent *outEvent);

/*  現在位置のイベントを置き換える。outEvent が NULL でなければ、古いイベントが *outEvent に返される。 */
MDStatus		MDPointerReplaceAnEvent(MDPointer *inPointer, const MDEvent *inEvent, MDEvent *outEvent);

/*  現在位置のイベントの tick を変更する。inPosition に変更後の位置を指定することができる。inPosition に動かすと
    tick 順に矛盾を生じる場合は、inTick の値に合わせて適当な位置を探す。inPointer は移動後のイベントの位置に移る。 */
MDStatus		MDPointerChangeTick(MDPointer *inPointer, MDTickType inTick, int32_t inPosition);

/*  Change the duration value, with clearing the largestTick cache in the MDBlock  */
MDStatus		MDPointerSetDuration(MDPointer *inPointer, MDTickType inDuration);

/*  Sanity check  */
MDStatus		MDPointerCheck(const MDPointer *inPointer);

/*  新しい MDTrackMerger をアロケートする。メモリ不足の場合は NULL を返す。 */
MDTrackMerger *	MDTrackMergerNew(void);

/*  Retain/release  */
void			MDTrackMergerRetain(MDTrackMerger *inMerger);
void			MDTrackMergerRelease(MDTrackMerger *inMerger);

/*  MDTrack を登録する。成功すれば現在のトラック数、失敗すれば -1 を返す。  */
int             MDTrackMergerAddTrack(MDTrackMerger *inMerger, MDTrack *inTrack);

/*  MDTrack の登録をやめる。現在のトラック数を返す。inTrack が登録されていなければ -1 を返す。  */
int             MDTrackMergerRemoveTrack(MDTrackMerger *inMerger, MDTrack *inTrack);

/*  num 番目のトラックを返す。存在しなければ NULL を返す。 */
MDTrack *       MDTrackMergerGetTrack(MDTrackMerger *inMerger, int num);
    
/*  inTick より小さくない tick 値を持つ最初のイベントの位置に移動し、そのイベントへの
 ポインタを返す。そのようなイベントが存在しなければ末尾以降に移動し、NULL を返す。 */
/*  outTrack が NULL でなければ、現在のイベントが属するトラックを返す。  */
MDEvent *       MDTrackMergerJumpToTick(MDTrackMerger *inMerger, MDTickType inTick, MDTrack **outTrack);

/*  現在のイベントへのポインタを得る。存在しないイベントを指している場合は NULL を返す。 */
/*  outTrack が NULL でなければ、現在のイベントが属するトラックを返す。  */
/* （呼ばれるたびにすべてのトラックの tick を比較するので注意）  */
MDEvent *		MDTrackMergerCurrent(MDTrackMerger *inMerger, MDTrack **outTrack);

/*  １つ先の位置に進み、そのイベントへのポインタを得る。最後のイベントを越えた場合は
 NULL を返す。 */
/*  outTrack が NULL でなければ、現在のイベントが属するトラックを返す。  */
MDEvent *		MDTrackMergerForward(MDTrackMerger *inMerger, MDTrack **outTrack);

/*  １つ前の位置に戻り、そのイベントへのポインタを得る。先頭のイベントを越えた場合は
 NULL を返す。 */
/*  outTrack が NULL でなければ、現在のイベントが属するトラックを返す。  */
MDEvent *		MDTrackMergerBackward(MDTrackMerger *inMerger, MDTrack **outTrack);

#ifdef __cplusplus
}
#endif

#endif  /*  __MDTrack__  */

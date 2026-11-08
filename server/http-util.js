'use strict';
/** 커뮤니티·순위 API 가 함께 쓰는 HTTP 도우미 (JSON 응답, 본문 읽기, CORS, 글자 수) */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, X-Admin-Key, Authorization',
  'Access-Control-Max-Age': '600',
};

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, Object.assign({
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Length': Buffer.byteLength(body),
  }, CORS));
  res.end(body);
}

function sendError(res, e, log) {
  if (e && typeof e.status === 'number' && e.status >= 400 && e.status < 600) {
    sendJson(res, e.status, { error: e.message });
  } else {
    (log || console.error)(`API 오류: ${e && e.stack ? e.stack : e}`);
    sendJson(res, 500, { error: '서버 오류가 났습니다. 잠시 뒤 다시 시도하세요.' });
  }
}

/** JSON 본문 → 객체 (비어 있으면 {}) */
function readJson(req, maxBytes) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    let done = false;
    req.on('data', (c) => {
      if (done) return;
      size += c.length;
      if (size > maxBytes) {
        done = true;
        reject(new HttpError(413, `보낸 내용이 너무 큽니다 (최대 ${Math.round(maxBytes / 1024)}KB)`));
        req.resume();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      if (done) return;
      done = true;
      const text = Buffer.concat(chunks).toString('utf8').replace(/^\uFEFF/, '');
      if (!text.trim()) { resolve({}); return; }
      let obj;
      try { obj = JSON.parse(text); } catch (_) { reject(new HttpError(400, 'JSON 형식이 잘못되었습니다')); return; }
      if (!obj || typeof obj !== 'object' || Array.isArray(obj)) { reject(new HttpError(400, '{ … } 형태의 JSON 을 보내세요')); return; }
      resolve(obj);
    });
    req.on('error', (e) => { if (!done) { done = true; reject(e); } });
  });
}

/** 경로 → 조각 배열 (각 조각 디코드) */
function pathParts(pathname) {
  return pathname.split('/').filter(Boolean).map((s) => { try { return decodeURIComponent(s); } catch (_) { return s; } });
}

/** 글자 수 (코드 포인트 기준 — 한글 한 글자 = 1) */
function charLen(s) {
  return Array.from(s).length;
}
function charSlice(s, n) {
  const a = Array.from(s);
  return a.length <= n ? s : a.slice(0, n).join('');
}

const segmenter = typeof Intl === 'object' && Intl.Segmenter ? new Intl.Segmenter('ko', { granularity: 'grapheme' }) : null;
/** 첫 글자(자소 결합·이모지까지 한 덩어리) */
function firstGrapheme(s) {
  if (!s) return '';
  if (segmenter) {
    for (const seg of segmenter.segment(s)) return seg.segment;
    return '';
  }
  return Array.from(s)[0] || '';
}

/** 대학생이 고르는 학교 — 학교 이름이 곧 학년 값. lib/core/problem.dart 의 kUniversities 와 같아야 한다. */
const UNIVERSITIES = [
  '한양대', '서울대', '연세대', '고려대', '서강대', '성균관대', '중앙대', '경희대', '한국외대', '서울시립대',
  '건국대', '동국대', '홍익대', '국민대', '숭실대', '세종대', '단국대', '광운대', '명지대', '상명대',
  '가톨릭대', '이화여대', '숙명여대', '서울과기대', '한국항공대', '인하대', '인천대', '아주대', '가천대', '한국공학대',
  '한국기술교육대', 'KAIST', 'POSTECH', 'UNIST', 'GIST', 'DGIST', '부산대', '경북대', '전남대', '충남대',
  '충북대', '전북대', '강원대', '경상국립대', '부경대', '울산대',
];
/** 모든 대학 공통 (목록에 없는 학교 학생의 학년 값이기도 하다) */
const UNIV_GENERIC = '대학생';

/** 고등·N수는 예전 가입자용 (새 가입은 받지 않는다) */
const GRADES = ['고1', '고2', '고3', 'N수', '취준', UNIV_GENERIC, ...UNIVERSITIES, '편입'];

/** 커뮤니티 글·댓글 옆에 보이는 신분 (가입할 때 고른 과정에서 만든다): 고2, N수생, 인하대생 … 여러 개면 " · " 로 잇는다. */
const IDENTITIES = ['고1', '고2', '고3', 'N수생', '취준생', UNIV_GENERIC, ...UNIVERSITIES.map((u) => `${u}생`), '편입생', '선생님'];

module.exports = { CORS, HttpError, sendJson, sendError, readJson, pathParts, charLen, charSlice, firstGrapheme, GRADES, IDENTITIES, UNIVERSITIES, UNIV_GENERIC };

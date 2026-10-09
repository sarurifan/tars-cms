// tars-cms: lightweight logger shim
// 上游源码引用了 '../../logger'（本意是 src/logger/ 目录），但该目录在上游仓库
// 缺失（历史遗留 bug）。Node require 解析顺序：先试 <path>.js 文件，再试同名目录，
// 因此本文件会被所有 require('../../logger') 自动命中，无需改动 5 处调用点。
// 优先使用 @tars/logs（TarsWeb 官方 logger，随 npm install 安装），失败则退化为 console。
'use strict';
let impl = null;
try {
    const TarsLogs = require('@tars/logs');
    impl = new TarsLogs('GatewayWeb', { level: 'info' });
    if (typeof impl.info !== 'function') throw new Error('bad logger impl');
} catch (e) {
    impl = null;
}
const fmt = (args) => args.map(a => {
    try { return typeof a === 'string' ? a : JSON.stringify(a); }
    catch (_) { return String(a); }
}).join(' ');
function emit(level, consoleFn, args) {
    const m = fmt(Array.from(args));
    if (impl) { try { impl[level](m); } catch (e) { consoleFn(m); } }
    else { consoleFn('[' + level.toUpperCase() + ']', m); }
}
module.exports = {
    info:  function(){ emit('info',  console.log, arguments); },
    error: function(){ emit('error', console.error, arguments); },
    warn:  function(){ emit('warn',  console.warn, arguments); },
    debug: function(){ emit('debug', console.log, arguments); },
    setLevel: function(){},
    close: function(){}
};

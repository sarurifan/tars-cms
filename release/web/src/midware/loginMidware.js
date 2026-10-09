const _ = require('lodash');
const AdminService = require('../common/AdminService');
const WebConf = require('../config/webConf');

let ignore = ['/plugins/base/server/api/get_locale'];

// tars-cms: 本地部署免登录白名单（localAuth.localIp）
// 上游未实现此字段 —— 容器内 curl 127.0.0.1 / 同网段运维调用被 AdminReg.checkTicket
// 挡死（AdminReg 在 K8s 集群外拿不到 TarsWeb ticket 时会 hang）。白名单内 IP 直接放行。
// 旁路时 ctx.uid 固定为 'local'，控制器把 'local' 视为管理员（可读写全部数据）。
function isLocalBypass(ctx) {
    const local = (WebConf && WebConf.localAuth && Array.isArray(WebConf.localAuth.localIp))
        ? WebConf.localAuth.localIp : [];
    if (!local.length) return false;
    const ip = ctx.ip || (ctx.request && ctx.request.ip) || '';
    return local.some(x => x === ip || ip.endsWith(x) || ip === '127.0.0.1');
}

module.exports = async (ctx, next) => {

	console.log(ctx.request.path);

	if (ignore.indexOf(ctx.request.path) == -1 && !isLocalBypass(ctx)) {

		let ticket = ctx.paramsObj.ticket || ctx.cookies.get("ticket") || ctx.request.header["x-token"];

		if (!ticket) {
			ctx.makeResObj(403, "no auth", {});
			return;
		}

		let uid = await AdminService.checkTicket(ticket);

		if (!uid) {
			ctx.makeResObj(403, "no auth", {});
			return;
		}

		ctx.uid = uid;
	} else {
		ctx.uid = 'local';
	}

	await next();

};

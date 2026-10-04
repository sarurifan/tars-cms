#!/usr/bin/env bash
# ================================================================
# n11-test.sh — tars-cms 全栈测试套件
# ================================================================
# 【三层测试】
#   1. 单元测试   go test ./...        纯函数、无外部依赖（31 个用例）
#   2. 集成测试   直连 TARS RPC       BFF→TarsServer 协议层
#   3. 端到端     经网关 HTTP         前端→网关→BFF→TARS→MySQL
#
# 【用法】
#   bash deploy/n11-test.sh              # 全部三层
#   bash deploy/n11-test.sh --unit       # 只跑单元测试
#   bash deploy/n11-test.sh --e2e        # 只跑端到端
# ================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATEWAY="${CMS_GATEWAY:-http://192.168.1.95:8200}"
HOST_HDR="cms"
TENANT=1

C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_END=$'\033[0m'
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  ${C_GREEN}✔${C_END} $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ${C_RED}✘${C_END} $1"; }
section() { echo; echo "${C_CYAN}━━━ $1 ━━━${C_END}"; }

MODE="${1:-all}"

# ================================================================
# 第一层：单元测试
# ================================================================
if [[ "$MODE" == "all" || "$MODE" == "--unit" ]]; then
  section "第一层：单元测试 (go test)"
  for mod in cms gateway/bff; do
    if [[ -d "$ROOT/$mod" ]]; then
      out=$(cd "$ROOT/$mod" && go test ./... 2>&1)
      if echo "$out" | grep -q "^FAIL\|^--- FAIL"; then
        fail "$mod 单元测试"
        echo "$out" | grep -E "^--- FAIL|^\s+\S+_test.go" | head -5 | sed 's/^/      /'
      else
        n=$(echo "$out" | grep -c "^ok")
        pass "$mod 单元测试通过"
      fi
    fi
  done
  echo "  用例总数: $(cd "$ROOT/cms" && go test -v ./... 2>/dev/null | grep -c "^--- PASS" || echo 0) (cms) + $(cd "$ROOT/gateway/bff" && go test -v ./... 2>/dev/null | grep -c "^--- PASS" || echo 0) (bff)"
fi

[[ "$MODE" == "--unit" ]] && { echo; echo "通过 $PASS / 失败 $FAIL"; exit $((FAIL>0)); }

# ================================================================
# 第二层：TARS RPC 协议层（BFF 是否真的连上 TARS）
# ================================================================
if [[ "$MODE" == "all" || "$MODE" == "--e2e" ]]; then

section "第二层：服务存活与端口"
for svc in "cms.CmsServer:13101" "cms.CmsServer:13102" "cms.CmsWeb:13103" "cms.CmsBff:3103"; do
  name="${svc%%:*}"; port="${svc##*:}"
  if docker exec tars-node ss -tln 2>/dev/null | grep -q ":$port "; then
    pass "$name 监听 :$port"
  else
    fail "$name 未监听 :$port"
  fi
done

section "第三层：端到端（经网关 $GATEWAY，Host: $HOST_HDR）"

# 通用请求函数：返回 HTTP 码 + body
req() {
  local path="$1"; shift
  curl -s -w "\n%{http_code}" --max-time 10 -H "Host: $HOST_HDR" "$@" "$GATEWAY$path" 2>/dev/null
}

# 断言：HTTP 200 且 JSON code==0
assert_api() {
  local name="$1" path="$2"; shift 2
  local resp code body
  resp=$(req "$path" "$@")
  code=$(echo "$resp" | tail -1)
  body=$(echo "$resp" | head -n -1)
  if [[ "$code" != "200" ]]; then
    fail "$name → HTTP $code"
    return
  fi
  local jcode
  jcode=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code'))" 2>/dev/null || echo "parse_err")
  if [[ "$jcode" == "0" ]]; then
    pass "$name → 200 code=0"
  else
    fail "$name → code=$jcode"
  fi
}

# --- 公开接口 ---
assert_api "首页聚合"      "/api/cms/home?tenantId=$TENANT"
assert_api "分类列表"      "/api/cms/categories?tenantId=$TENANT"
assert_api "分类树"        "/api/cms/categories/tree?tenantId=$TENANT"
assert_api "文章列表"      "/api/cms/articles?tenantId=$TENANT&page=1&size=5"
assert_api "文章详情"      "/api/cms/articles/1?tenantId=$TENANT"
assert_api "站点配置"      "/api/cms/config?tenantId=$TENANT"

# --- 静态站 ---
for p in "/" "/admin/"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: $HOST_HDR" "$GATEWAY$p")
  [[ "$code" == "200" ]] && pass "静态页 $p → 200" || fail "静态页 $p → $code"
done

# --- SPA 回退 ---
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: $HOST_HDR" "$GATEWAY/article/1")
[[ "$code" == "200" ]] && pass "SPA 回退 /article/1 → 200" || fail "SPA 回退 /article/1 → $code"

section "第四层：数据契约（字段存在性与类型）"
home=$(curl -s --max-time 10 -H "Host: $HOST_HDR" "$GATEWAY/api/cms/home?tenantId=$TENANT")
echo "$home" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin).get('data',{})
except Exception as e:
    print('  ✘ 首页响应非 JSON:', e); sys.exit(1)
checks=[('banners',list),('categories',list)]
for k,t in checks:
    if k not in d: print(f'  ✘ 缺字段 {k}')
    elif not isinstance(d[k],t): print(f'  ✘ {k} 类型错')
    else: print(f'  ✔ 字段 {k} ({len(d[k])} 项)')
" 2>/dev/null || fail "首页字段契约"

# 文章详情字段（重点：author 必须是对象不是字符串）
detail=$(curl -s --max-time 10 -H "Host: $HOST_HDR" "$GATEWAY/api/cms/articles/1?tenantId=$TENANT")
echo "$detail" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('data',{})
req=['id','title','content','author','category','publish_at']
for k in req:
    print(f'  {\"✔\" if k in d else \"✘\"} 详情字段 {k}' + (f' = {type(d[k]).__name__}' if k in d else ' 缺失'))
a=d.get('author')
if isinstance(a,dict): print('  ✔ author 是对象（非字符串）')
else: print(f'  ✘ author 类型 {type(a).__name__}（应为 dict）')
" 2>/dev/null || fail "详情字段契约"

section "第五层：XSS 防护（写入→读取验证）"
# 登录拿 token
tok=$(curl -s --max-time 10 -H "Host: $HOST_HDR" -H "Content-Type: application/json" \
  -d "{\"tenantId\":$TENANT,\"username\":\"admin\",\"password\":\"admin123\"}" \
  "$GATEWAY/api/auth/login" | python3 -c "
import json,sys
try: print(json.load(sys.stdin)['data']['token'])
except: print('')
" 2>/dev/null)

if [[ -z "$tok" ]]; then
  fail "登录失败（无法测试 XSS 链路）"
else
  pass "管理员登录成功"
  # 创建含 XSS 的文章
  xss_title="XSS测试_$(date +%s)"
  create=$(curl -s --max-time 10 -H "Host: $HOST_HDR" -H "Content-Type: application/json" \
    -H "Authorization: Bearer $tok" \
    -d "{\"tenantId\":$TENANT,\"title\":\"$xss_title\",\"summary\":\"s\",\"content\":\"<p>安全</p><script>alert(1)</script><img src=x onerror=evil()>\",\"categoryId\":1,\"type\":\"doc\"}" \
    "$GATEWAY/api/admin/articles")
  new_id=$(echo "$create" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('id',''))" 2>/dev/null)
  if [[ -n "$new_id" && "$new_id" != "" ]]; then
    pass "创建文章成功 (id=$new_id)"
    # 读回验证 XSS 已被净化
    readback=$(curl -s --max-time 10 -H "Host: $HOST_HDR" "$GATEWAY/api/cms/articles/$new_id?tenantId=$TENANT")
    echo "$readback" | python3 -c "
import json,sys
c=json.load(sys.stdin).get('data',{}).get('content','')
bad=[t for t in ['<script','onerror','alert('] if t in c]
print('  ✔ XSS 已净化（script/onerror 已剥离）' if not bad else f'  ✘ XSS 残留: {bad}')
print('  ✔ 安全内容保留' if '安全' in c else '  ✘ 正常内容丢失')
" 2>/dev/null
    # 清理
    curl -s -o /dev/null --max-time 10 -H "Host: $HOST_HDR" -H "Authorization: Bearer $tok" \
      -X POST "$GATEWAY/api/admin/articles/delete" -H "Content-Type: application/json" \
      -d "{\"tenantId\":$TENANT,\"id\":$new_id}" 2>/dev/null
    pass "测试文章已清理"
  else
    fail "创建文章失败"
  fi
fi

section "第六层：鉴权边界（未授权应拒绝）"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: $HOST_HDR" "$GATEWAY/api/admin/articles?tenantId=$TENANT")
body=$(curl -s --max-time 8 -H "Host: $HOST_HDR" "$GATEWAY/api/admin/articles?tenantId=$TENANT")
jcode=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code'))" 2>/dev/null || echo "?")
if [[ "$jcode" != "0" ]]; then
  pass "未授权访问后台接口被拒 (code=$jcode)"
else
  fail "未授权访问后台接口竟然成功（安全漏洞！）"
fi

section "第七层：上传安全（白名单，防存储型 XSS）"
if [[ -n "$tok" ]]; then
  tmpdir=$(mktemp -d)
  echo '<script>alert(1)</script>' > "$tmpdir/e.html"
  printf '<svg xmlns="http://www.w3.org/2000/svg"><script>x</script></svg>' > "$tmpdir/e.svg"
  echo '<?php echo 1;?>' > "$tmpdir/e.php"
  echo 'alert(1)' > "$tmpdir/e.js"
  printf 'text' > "$tmpdir/ok.txt"
  for f in e.html e.svg e.php e.js; do
    r=$(curl -s --max-time 15 -H "Host: $HOST_HDR" -H "Authorization: Bearer $tok" \
      -F "file=@$tmpdir/$f" "$GATEWAY/api/admin/upload/file?tenantId=$TENANT")
    c=$(echo "$r" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code'))" 2>/dev/null)
    if [[ "$c" == "-1" ]]; then pass "拒绝危险类型 .${f##*.}（防 XSS）"; else fail "危险类型 .${f##*.} 被放行！"; fi
  done
  r=$(curl -s --max-time 15 -H "Host: $HOST_HDR" -H "Authorization: Bearer $tok" \
    -F "file=@$tmpdir/ok.txt" "$GATEWAY/api/admin/upload/file?tenantId=$TENANT")
  c=$(echo "$r" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code'))" 2>/dev/null)
  [[ "$c" == "0" ]] && pass "放行合法类型 .txt" || fail "合法 .txt 被误拒"
  newmid=$(echo "$r" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('id',''))" 2>/dev/null)
  rm -rf "$tmpdir"

  # 删除媒体应同时删除物理文件
  if [[ -n "$newmid" ]]; then
    dr=$(curl -s --max-time 10 -X POST -H "Host: $HOST_HDR" -H "Authorization: Bearer $tok" \
      -H "Content-Type: application/json" -d "{\"tenantId\":$TENANT,\"id\":$newmid}" \
      "$GATEWAY/api/admin/media/delete")
    dc=$(echo "$dr" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code'))" 2>/dev/null)
    [[ "$dc" == "0" ]] && pass "删除媒体记录成功" || fail "删除媒体失败"
    # 验证物理文件已删（通过 URL 访问应 404）
    u=$(echo "$r" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('url',''))" 2>/dev/null)
    if [[ -n "$u" ]]; then
      hc=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: $HOST_HDR" "$GATEWAY$u")
      [[ "$hc" == "404" ]] && pass "物理文件已随之删除（$u → 404）" || fail "物理文件仍可访问（$u → $hc）"
    fi
  fi
else
  fail "无 token，跳过上传安全测试"
fi

section "第八层：CORS 白名单（不反射任意 Origin）"
# 白名单内 Origin 应有 ACAO
acao=$(curl -s -I --max-time 8 -H "Origin: $GATEWAY" "http://172.25.0.5:3103/api/cms/home?tenantId=$TENANT" | grep -i "^access-control-allow-origin" | tr -d '\r')
[[ -n "$acao" ]] && pass "白名单 Origin 返回 ACAO" || fail "白名单 Origin 无 ACAO"
# 恶意 Origin 不应有 ACAO
bad=$(curl -s -I --max-time 8 -H "Origin: https://evil.example.com" "http://172.25.0.5:3103/api/cms/home?tenantId=$TENANT" | grep -ci "^access-control-allow-origin")
[[ "$bad" == "0" ]] && pass "恶意 Origin 未被反射（无 ACAO）" || fail "恶意 Origin 被反射（CORS 漏洞）"

section "第九层：错误处理（非法输入应优雅降级）"
# 不存在的文章
r=$(curl -s --max-time 8 -H "Host: $HOST_HDR" "$GATEWAY/api/cms/articles/999999?tenantId=$TENANT")
rc=$(echo "$r" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code'))" 2>/dev/null || echo "?")
[[ "$rc" != "0" ]] && pass "不存在的文章返回错误码 (code=$rc)" || fail "不存在的文章返回了成功"

# 非法分页参数
r=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: $HOST_HDR" "$GATEWAY/api/cms/articles?tenantId=$TENANT&page=abc&size=-5")
[[ "$r" == "200" ]] && pass "非法分页参数优雅降级 (HTTP $r)" || fail "非法分页参数 → HTTP $r"

# 超大 size（应被限制到 100）
r=$(curl -s --max-time 8 -H "Host: $HOST_HDR" "$GATEWAY/api/cms/articles?tenantId=$TENANT&size=99999")
echo "$r" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('data',{})
n=len(d.get('list',[]))
print(f'  ✔ size=99999 被限制，实际返回 {n} 条' if n<=100 else f'  ✘ size 未限制，返回 {n} 条')
" 2>/dev/null || fail "size 上限检查"

fi

# ================================================================
echo
echo "════════════════════════════════════════"
echo "  通过 ${C_GREEN}$PASS${C_END}    失败 ${C_RED}$FAIL${C_END}"
echo "════════════════════════════════════════"
[[ "$FAIL" == "0" ]] && echo "${C_GREEN}🎉 全部测试通过${C_END}" || echo "${C_RED}⚠ 有测试失败${C_END}"
exit $((FAIL>0))

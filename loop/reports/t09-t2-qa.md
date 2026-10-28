# T09-T2 QA 验收报告：可配置生效全链+手柄死区（只验不修）——兼 T08 两项补验收口

> 验收对象：分支 `loop/t09-actions`（自 main 96656896），提交 **d0c2c959** `Make action bindings editable and wire the gamepad deadzones`（5 文件 +551/−14，与程序报告一致）。工作区核对：与提交态一致。
> 证据：`loop/t09t2_qa_live2.log`（QA 五项真机复跑）、`loop/t08t3_qa_final4.log`+`loop/t08t3_stopcard.log`（T08 两补验）、`loop/t09t2_*`（程序归档六件）、QA 亲跑输出。

## 一、门禁——干净（归档+亲跑双过）

归档全文复核：fmt 空；clippy 0 error；lib **1176**/0；guards **210**/0（50.45s）；crates（runtime **38**/0+scaffold **82**/0）；nextest integration **5235 passed / 2 skipped**（347s，1 slow 1 leaky 系 nextest 标注非失败）。QA 亲跑：runtime 38/0、enum 形态用例 ok、guards 全量 **210/0**（53.06s）。✅

## 二、三层缺口红绿 review——全部成立，无新 🔴/🟡

### 缺口 1：schema crate 过滤豁免（边界审通过）

判据 `is_project_crate(segment) || (segment == "jackdaw_runtime" && has ReflectResource)`。**边界核实**：①精确匹配单 crate 名（非前缀）——其它 jackdaw_ crate 零误豁免面；②**影响面终核**——runtime crate 产品代码 Asset 类型恰 **2 个**（GameInputConfig=Asset+Resource→豁免；JackdawScene=Asset 无 Resource→Resource 半判据正确挡住保持滤除；config.rs:216 与 lib.rs:1914 两处 derive Asset 均在 `#[cfg(test)]` 内不进注册表——程序「仅两个 Asset 类型，收窄为 1」数字正确）；③GameConfig（T08）在游戏 crate（is_project_crate 原路）与 GameInputConfig（runtime crate 豁免路）双路并存自洽。guards `the_runtime_config_assets_reach_the_new_asset_list` 红绿（红=`[]` 整体滤掉）。✅

### 缺口 2：enum 单字段 tuple variant serde 等价

`variant.fields.len()==1 && !body.is_object()` 时按单元素 tuple 解析——serde 直给形态 `"Key":"ArrowUp"` 与 wrapped `["ArrowUp"]` 两拼写同建 `TupleStruct`；struct/unit variant 不受影响（`!body.is_object()` 守卫）。用例**四态全覆盖**（direct/wrapped/struct/unit），QA 亲跑 ok。⚪ 既有边界记档（非本修复引入）：单字段 tuple variant 字段为 object 型时 object body 走 struct 路径解析失败——当前绑定 enum 无此形态（Key/MouseButton/GamepadButton 均 enum 字段=string 形态）。✅

### 缺口 3：手柄死代码破案（QA 对照 c9c397b bevy 树逐条核实成立）

- **bevy main 无全局 `ButtonInput<GamepadButton>`/`Axis<GamepadAxis>` 资源**（gilrs_systems/gamepad.rs 无相应 init_resource）；状态在 `Gamepad` **Component**（`reflect(Component)`+`require(GamepadSettings)`）的 `digital: ButtonInput<GamepadButton>`/`analog: Axis<GamepadInput>` 字段——T1 的 `Option<Res<...>>` 读法永远 None=死代码，破案正确。✅
- 修复 `Query<&Gamepad>`：any-pad 并集（按钮任一柄按住即按住——与 bevy 单 enum 按钮键的全手柄并集语义一致）；轴取各柄**最大偏转**（多柄冲突取主导——合理保守）；死区由引擎 `GamepadSettings` 过滤后读数（`gamepad.get()`）。
- 红证形态：main 形态 mock 回退模拟红（T07-T2 P5 先例）——接受（main 上无测试且 API 已不存在，唯一可行）。
- 合成事件用例（RawGamepadEvent 与 gilrs/PIE 同流）钉死全链：过死区驱动/死区内滤除/South just_pressed。✅

## 三、真机五项——QA 独立复跑全 PASS（数字级复现程序归档）

`loop/t09t2_qa_live2.log`（工程 t09t2-game，QA 复跑）：

| 项 | QA 复跑数字 | 程序归档 | 判定 |
|---|---|---|---|
| ①改绑三态 | asset.new ok+盘上完整形态（ArrowUp/LeftStickX/0.5/LMB 全保留——缺口 1+2 真机实证）；Play 后 **ArrowUp dz=-12.20**、**W dz=0** | -11.9 / 0 | PASS |
| ②capture 生命周期三轮 | toggle 激活→动；**Shift+Esc 真弦释放→dz=0**；再 toggle→**dz=-11.90** | 同链 | PASS |
| ③手柄实体 | 本机 0 设备（复跑同）——**挂账口径裁定：接受**（合成事件全链红绿+windowless 保留 GilrsPlugin 代码实证+决策 5-A 无协议扩展论证齐；实体腿挂 open-challenges/有硬件时复验） | 0 设备 | 机制 PASS/实体挂账 |
| ④PlayerMarker 两帧差 | ITEM4 直证（dz 见①——复跑顺带覆盖，同断言同通道） | 投影 20 实体 | PASS |
| ⑤I3 mouse 腿 | dx=240 → **yaw=-0.932039**（与程序归档 -0.932 **逐位一致**，量纲精确吻合非弱断言） | -0.932 | PASS |

## 四、真机工程处置（QA 裁定）

- **t09t2-game 保留给 T3**（PlayerMarker/输入链/capture 已暖，矩阵断言直接复用；T09 收尾统一清理）。
- **t08lf-qa 已删**（T08 补验完成后处置，`loop/qa-fixture/` 清空）；测试资产 t08stop.bsn 已清。

## 五、⚪ watcher 时序裁定

「idle 放行≠schema kinds 就位」：**记 buglist/open-challenges backlog**（程序建议的启动时对现有 schema.json 初始刷新属编辑器侧低成本改进，值得排期）；T3 矩阵脚本沿用轮询吸收模式（t09-t2-live.ps1 的 40×5s 轮询已沉淀可复用样板）。不阻塞本任务。

## 六、偏差 5 条裁定——全部接受

1. 三缺口系任务书「适配缺口」的子层拆分（schema 过滤更前置+enum serde 更深层+手柄死代码新发现）——接受（三层独立红绿齐备）；
2. 实体手柄挂账（无硬件）——接受（§三③）；
3. watcher 时序——接受+backlog（§五）；
4. guards 编辑器侧注册（init_asset 同构注册，writer/read 形态同一）——接受；
5. mouse 腿量纲验证——接受（QA 复跑 -0.932039 逐位复现）。

## 七、T08 两项补验收口——全部销案

**环境归因更新（重要）**：本轮 QA 双脚本并发时的「editor died booting」系 **QA 编排失误**（T2 脚本开头的全局 kill 误杀 T08 脚本刚 spawn 的编辑器，错峰方向反了）；另有 **exe 与 deps 的 dll 失配**（`cargo build -p jackdaw` 重编 38 秒后恢复，同 T09-T0 时 jd.exe 0xC0000135）——**此前「机器劣化冻结」的归因需修正：至少 dll 失配这一构件可用重编排除**；真正装载冻结是否仍存待观察（本轮重编后一切正常，与程序「5 轮全通」一致）。T08 终验报告的降级口径维持有效（证据本就交叉充分），补验为补强。

- **补验①（C2/C7 独立直证）PASS 销案**：第四轮干净单跑（`t08t3_qa_final4.log`）——**C2** 重启后盘上 3.25 幸存（disk-survived=True；card-reads=False 系 QA 探针对 asset.get result 形态的匹配问题，非产品——盘上文件直验为准）；**C7** dirty 卡 7.5→export→**同步落盘 True+dist 含 7.5 True+manifest 列出 True**（第三轮 C7 FAIL 系 QA 脚本前置缺陷——重启会话未重开卡致 asset.set no-op，修正 asset.open 后过——**产品链全程无恙**）。T08 验收句三态的①重启②Play（T2 轮 gravity/ms 实测）③导出三腿现全部有 QA 独立直证。
- **补验②（stop 关卡主路径）PASS 销案**：`t08t3_stopcard.log`——play/stop 存活+**post-stop asset.set 报告 "Set perceptual_roughness"（卡片保持打开可编辑）**+盘上 0.6（启动链落盘佐证）。评审②修复主路径实证生效；**残留多路径（C5b 之外的 close 调用）仍挂 open-challenges**（与终验口径一致）。

**T08 尾巴全部清偿**：补验条件①②销案，建议主控记台账（T08 全闭环）。

## 八、结论

三层缺口核实（破案对 bevy 树成立+边界审过+影响面数字正确）；真机五项独立复跑全 PASS（含 -0.932 逐位复现）；门禁归档+亲跑干净；偏差 5 条接受；T08 两项补验收口销案；工程处置完毕（t09t2-game 留 T3、t08lf-qa 已删）。

VERDICT: PASS（T09-T2 验收通过，建议主控 --no-ff 合入；T08 两项补验同步销案建议记台账——T08 至此全闭环；T3 前置：矩阵断言沿用 t09t2-game 工程+轮询样板；backlog：watcher 时序初始刷新+实体手柄复验+stop 关卡残留多路径）

# Issue tracker：本地文件

本仓库的票是文件，不进任何远程 tracker。

## 约定

- 一个功能一个目录：`docs/.workings/<slug>/`
- 票是 `docs/.workings/<slug>/issues/<NN>-<slug>.md`，从 `01` 起按依赖顺序编号
- 一票一文件，不得合并
- 依赖写在文件靠前处的 `Blocked by:` 行
- 状态写在靠前处的 `Status:` 行；agent 可取的票使用 `ready-for-agent`
- 对话与补充追加在文件末尾的 `## Comments` 下

## spec 不在这里

spec 是长期维护的结论，保存到 `docs/specs/<slug>.md`。
`docs/.workings/` 只保存施工票与 review 记录。

## skill 发票时

在 `docs/.workings/<slug>/issues/` 下新建一份文件。

## skill 取票时

读取用户指定的路径或编号。

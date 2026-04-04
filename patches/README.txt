super_editor 0.3.0-dev.23：删除图片后撤销时，若选区对应的组件尚未完成布局，
getRectForSelection 可能为 null，库内对返回值使用 ! 会崩溃。本目录补丁对 Android / iOS
触摸手势里 _ensureSelectionExtentIsVisible 做空判断。

在重新执行 flutter pub get 或换机后，若需再次打补丁，在包根目录执行（路径按本机 Pub 缓存调整）：

  cd %LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\super_editor-0.3.0-dev.23
  git apply <项目根目录>\patches\super_editor_touch_getRect_null_safe.patch

若补丁已应用过，git apply 会报错，可忽略或先用 git checkout 还原包内文件再打补丁。

长期方案：向 super_editor 上游提 PR，或使用 dependency_overrides 指向已合并修复的分支。

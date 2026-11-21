// Load this function in the Computer Use JavaScript session. Keep the same
// replay instance across system authentication dialogs.
function libreShotPermissionReplay(settings, permission, version) {
    const panes = { input: "输入监控", screen: "录屏与系统录音" };
    const pane = panes[permission];
    if (!pane || !/^\d+(\.\d+)+$/.test(version)) {
        throw new Error("Expected an input or screen permission and an installed version.");
    }

    const appPath = "/Applications/LibreShot.app";
    const read = () => settings.getAXState({ emit: false, disableDiffing: true });
    const authenticating = state => /正在尝试修改你的系统设置|按钮 使用密码|使用触控ID或输入密码/.test(state);
    const onPage = (state, title) => state.startsWith(`Window: "${title}", App:`);
    const choosing = state => /对话框 打开, ID: open-panel/.test(state);
    const selectedFile = state =>
        /文本栏 \(selected, settable\) URL: file:\/\/\/Applications\/LibreShot\.app\//.test(state) &&
        state.split("\n").some(line => line.includes("text LibreShot.app") && line.includes(`版本 ${version} `));
    let phase = "navigate";

    function uniqueIndex(state, pattern) {
        const matches = state.split("\n").filter(line => pattern.test(line));
        return matches.length === 1 ? Number(matches[0].trim().match(/^\d+/)[0]) : undefined;
    }

    function permissionList(state) {
        return permission === "screen" ? state.split(/\n\s*\d+ text 仅系统录音/)[0] : state;
    }

    return async function run() {
        let state = await read();
        while (true) {
            if (authenticating(state)) return { status: "authentication", phase };
            if (phase === "navigate") {
                if (!onPage(state, pane)) {
                    if (!onPage(state, "隐私与安全")) {
                        const privacy = uniqueIndex(state, /row \(selectable\) 隐私与安全\s*$/);
                        const back = uniqueIndex(state, /按钮 Description: 返回, ID: chevron\.backward/);
                        const navigation = /row \(selected\) 隐私与安全/.test(state) ? back : privacy;
                        if (navigation === undefined) return { status: "blocked", phase };
                        await settings.click(navigation);
                        state = await read();
                    }
                    if (!onPage(state, "隐私与安全")) return { status: "blocked", phase };
                    const destination = uniqueIndex(state, new RegExp(`按钮 Description: ${pane}(?:[、,]|$)`));
                    if (destination === undefined) return { status: "blocked", phase };
                    await settings.click(destination);
                    state = await read();
                }
                if (!onPage(state, pane)) return { status: "blocked", phase };
                const list = permissionList(state);
                const oldRow = uniqueIndex(list, /row \(selectable\) LibreShot\.app\s*$/);
                if (oldRow !== undefined) {
                    await settings.click(oldRow);
                    state = await read();
                }
                if (!onPage(state, pane)) return { status: "blocked", phase };
                const selectedRow = uniqueIndex(permissionList(state), /row \(selected\) LibreShot\.app\s*$/);
                const remove = uniqueIndex(permissionList(state), /按钮 移除\s*$/);
                if (selectedRow !== undefined && remove !== undefined) {
                    phase = "removed";
                    await settings.click(remove);
                    state = await read();
                } else if (/row .*LibreShot\.app/.test(permissionList(state))) {
                    return { status: "blocked", phase };
                }
                phase = "removed";
            } else if (phase === "removed") {
                const list = permissionList(state);
                if (!onPage(state, pane) || /row .*LibreShot\.app/.test(list)) return { status: "blocked", phase };
                const add = uniqueIndex(list, /按钮 添加\s*$/);
                if (add === undefined) return { status: "blocked", phase };
                phase = "choose";
                await settings.click(add);
                state = await read();
            } else if (phase === "choose") {
                if (!choosing(state)) return { status: "blocked", phase };
                if (!selectedFile(state)) {
                    await settings.pressKey("super+shift+g");
                    await settings.paste(appPath);
                    await settings.pressKey("Return");
                    state = await read();
                }
                if (authenticating(state)) return { status: "authentication", phase };
                if (!selectedFile(state) || uniqueIndex(state, /按钮 打开, ID: OKButton/) === undefined) {
                    return { status: "blocked", phase };
                }
                phase = "opened";
                await settings.pressKey("Return");
                state = await read();
                const open = uniqueIndex(state, /按钮 打开, ID: OKButton/);
                if (!authenticating(state) && choosing(state) && selectedFile(state) && open !== undefined) {
                    await settings.click(open);
                    state = await read();
                }
            } else {
                if (!onPage(state, pane)) return { status: "blocked", phase };
                const list = permissionList(state);
                const on = /转换 Value: on, ID: LibreShot\.app_Toggle/.test(list);
                if (!on) {
                    const toggle = uniqueIndex(list, /转换 Value: off, ID: LibreShot\.app_Toggle/);
                    if (toggle === undefined) return { status: "blocked", phase };
                    await settings.click(toggle);
                    state = await read();
                    if (authenticating(state)) return { status: "authentication", phase };
                }
                return {
                    status: onPage(state, pane) && /转换 Value: on, ID: LibreShot\.app_Toggle/.test(permissionList(state))
                        ? "enabled" : "blocked",
                    phase
                };
            }
        }
    };
}

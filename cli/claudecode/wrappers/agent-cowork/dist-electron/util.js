import { ipcMain } from "electron";
import { getUIPath } from "./pathResolver.js";
import { pathToFileURL } from "url";
const PORT = 10087;
// Checks if you are in development mode
export function isDev() {
    return process.env.NODE_ENV == "development";
}
// Making IPC Typesafe
export function ipcMainHandle(key, handler) {
    ipcMain.handle(key, (event, ...args) => {
        if (event.senderFrame)
            validateEventFrame(event.senderFrame);
        return handler(event, ...args);
    });
}
export function ipcWebContentsSend(key, webContents, payload) {
    webContents.send(key, payload);
}
export function validateEventFrame(frame) {
    if (isDev() && new URL(frame.url).host === `localhost:${PORT}`)
        return;
    if (frame.url !== pathToFileURL(getUIPath()).toString())
        throw new Error("Malicious event");
}

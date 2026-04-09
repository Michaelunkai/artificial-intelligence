"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const electron_1 = __importDefault(require("electron"));
electron_1.default.contextBridge.exposeInMainWorld("electron", {
    subscribeStatistics: (callback) => ipcOn("statistics", stats => {
        callback(stats);
    }),
    getStaticData: () => ipcInvoke("getStaticData"),
    // Claude Agent IPC APIs
    sendClientEvent: (event) => {
        electron_1.default.ipcRenderer.send("client-event", event);
    },
    onServerEvent: (callback) => {
        const cb = (_, payload) => {
            try {
                const event = JSON.parse(payload);
                callback(event);
            }
            catch (error) {
                console.error("Failed to parse server event:", error);
            }
        };
        electron_1.default.ipcRenderer.on("server-event", cb);
        return () => electron_1.default.ipcRenderer.off("server-event", cb);
    },
    generateSessionTitle: (userInput) => ipcInvoke("generate-session-title", userInput),
    getRecentCwds: (limit) => ipcInvoke("get-recent-cwds", limit),
    selectDirectory: () => ipcInvoke("select-directory")
});
function ipcInvoke(key, ...args) {
    return electron_1.default.ipcRenderer.invoke(key, ...args);
}
function ipcOn(key, callback) {
    const cb = (_, payload) => callback(payload);
    electron_1.default.ipcRenderer.on(key, cb);
    return () => electron_1.default.ipcRenderer.off(key, cb);
}

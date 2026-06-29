sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/ui/model/json/JSONModel",
    "sap/ui/core/ValueState",
    "sap/m/MessageBox"
], function(Controller, JSONModel, ValueState, MessageBox) {
    "use strict";

    return Controller.extend("zewm005.controller.Main", {

        onInit: function() {
            // 本地数据模型：HU Barcode 表格
            this._huData = { items: [], count: 0 };
            var oHuModel = new JSONModel(this._huData);
            this.getView().setModel(oHuModel, "huModel");

            // 字段值缓存
            this._values = { destLoc: "", huBarcode: "" };
            this._lastInputId = "";

            // 全局事件监听
            this._focusHandler = this._onFocus.bind(this);
            document.addEventListener("focusin", this._focusHandler);
            this._keyHandler = this._onKeyDown.bind(this);
            document.addEventListener("keydown", this._keyHandler);
        },

        onExit: function() {
            document.removeEventListener("focusin", this._focusHandler);
            document.removeEventListener("keydown", this._keyHandler);
        },

        /* ── 焦点追踪 ────────────────────────────────────────── */
        _onFocus: function(oEvent) {
            var sShortId = oEvent.target.id.replace(/-inner$/, "").split("--").pop();
            var oControl = this.getView().byId(sShortId);
            if (oControl && oControl.setValue) {
                this._lastInputId = sShortId;
            }
        },

        /* ── LiveChange 处理 ─────────────────────────────────── */
        onDestLocLiveChange: function(oEvent) {
            this._values.destLoc = oEvent.getParameter("value");
        },

        onHUBarcodeLiveChange: function(oEvent) {
            this._values.huBarcode = oEvent.getParameter("value");
        },

        /* ── 键盘事件处理 ────────────────────────────────────── */
        _onKeyDown: function(oEvent) {
            if (oEvent.key === "Enter") {
                this._onEnter();
                return;
            }
            switch (oEvent.key) {
                case "F2": oEvent.preventDefault(); this.onClear(); break;
                case "F3": oEvent.preventDefault(); this.onRefresh(); break;
                case "F7": oEvent.preventDefault(); this.onBack(); break;
                case "F9": oEvent.preventDefault(); this.onConfirm(); break;
            }
        },

        _onEnter: function() {
            var oActive = document.activeElement;
            if (!oActive) { return; }
            var sDomValue = oActive.value || "";
            var sShortId = oActive.id.replace(/-inner$/, "").split("--").pop();

            if (sShortId === "destLoc") {
                this.onDestLocSubmit(sDomValue);
            } else if (sShortId === "huBarcode") {
                this.onHUBarcodeSubmit(sDomValue);
            }
        },

        /* ── 字段提交 ────────────────────────────────────────── */
        onDestLocSubmit: function(sDomValue) {
            var oInput = this.byId("destLoc");
            if (!oInput) { return; }
            var sValue = (sDomValue || this._values.destLoc || oInput.getValue() || "").trim();

            if (!sValue) {
                this._showError(oInput, this._i18n("msgDestLocMandatory"));
                return;
            }
            this._values.destLoc = sValue;
            this._clearError(oInput);

            // 验证目的地是否存在
            this._callApi("check_dest", { destLoc: sValue },
                function() {
                    var oNext = this.byId("huBarcode");
                    if (oNext) { oNext.focus(); }
                }.bind(this),
                function(sMsg) {
                    var sMsg2 = sMsg;
                    if (!sMsg || sMsg === "Request failed") {
                        sMsg2 = this._i18n("msgDestLocNotExist", [sValue]);
                    }
                    this._showError(oInput, sMsg2);
                }.bind(this),
                "ZEWM005-CHECK-DEST"
            );
        },

        onHUBarcodeSubmit: function(sDomValue) {
            var oInput = this.byId("huBarcode");
            if (!oInput) { return; }
            var sValue = (sDomValue || this._values.huBarcode || oInput.getValue() || "").trim();

            if (!sValue) { return; }

            this._values.huBarcode = sValue;
            this._clearError(oInput);

            // 验证 HU 是否存在
            this._callApi("check_hu", { hu: sValue },
                function() {
                    // 验证通过，加入表格
                    this._addHUToTable(sValue);
                    oInput.setValue("");
                    this._values.huBarcode = "";
                    oInput.focus();
                }.bind(this),
                function(sMsg) {
                    var sMsg2 = sMsg;
                    if (!sMsg || sMsg === "Request failed") {
                        sMsg2 = this._i18n("msgHUNotExist", [sValue]);
                    }
                    this._showError(oInput, sMsg2);
                }.bind(this),
                "ZEWM005-CHECK-HU"
            );
        },

        /* ── HU 表格操作 ──────────────────────────────────────── */
        _addHUToTable: function(sBarcode) {
            this._huData.items.push({
                seq: this._huData.items.length + 1,
                barcode: sBarcode
            });
            this._huData.count = this._huData.items.length;
            this.getView().getModel("huModel").refresh(true);
        },

        _clearHUTable: function() {
            this._huData.items = [];
            this._huData.count = 0;
            this.getView().getModel("huModel").refresh(true);
        },

        /* ── 功能键 ──────────────────────────────────────────── */
        onBack: function() {
            window.history.go(-1);
        },

        onClear: function() {
            var sShortId = this._lastInputId;
            if (!sShortId) { return; }
            var oControl = this.getView().byId(sShortId);
            if (oControl && oControl.setValue) {
                oControl.setValue("");
                this._values[sShortId] = "";
                this._clearError(oControl);
            }
        },

        onRefresh: function() {
            // 清空所有字段
            ["destLoc", "huBarcode"].forEach(function(sId) {
                var oCtrl = this.byId(sId);
                if (oCtrl && oCtrl.setValue) {
                    oCtrl.setValue("");
                    this._clearError(oCtrl);
                }
            }.bind(this));
            this._values = { destLoc: "", huBarcode: "" };

            // 清空表格
            this._clearHUTable();

            // 聚焦第一个输入框
            var oInput = this.byId("destLoc");
            if (oInput) { oInput.focus(); }
        },

        onConfirm: function() {
            var oDestInput = this.byId("destLoc");
            var sDestLoc = (this._values.destLoc
                || (oDestInput && oDestInput.getValue())
                || "").trim();

            if (!sDestLoc) {
                if (oDestInput) {
                    this._showError(oDestInput, this._i18n("msgDestLocMandatory"));
                    oDestInput.focus();
                } else {
                    MessageBox.error(this._i18n("msgDestLocMandatory"));
                }
                return;
            }

            if (this._huData.items.length === 0) {
                MessageBox.warning(this._i18n("msgNoHU"));
                var oHuInput = this.byId("huBarcode");
                if (oHuInput) { oHuInput.focus(); }
                return;
            }

            // 收集所有 HU Barcode
            var aHUs = this._huData.items.map(function(o) { return o.barcode; });

            this._callApi("confirm", {
                    destLoc: sDestLoc,
                    hus: aHUs
                },
                function(oData) {
                    try {
                        if (oData.restype === "E") {
                            MessageBox.error(oData.resmsg || this._i18n("msgConfirmFailed"));
                        } else if (oData.restype === "W") {
                            MessageBox.warning(oData.resmsg || this._i18n("msgConfirmWarning"));
                        } else {
                            MessageBox.success(oData.resmsg || this._i18n("msgConfirmSuccess"));
                            this.onRefresh();
                        }
                    } catch (e) {
                        MessageBox.error("Error: " + (e.message || e));
                    }
                }.bind(this),
                function(sMsg) {
                    MessageBox.error(sMsg || "Confirm request failed");
                },
                "ZEWM005-CONFIRM"
            );
        },

        /* ── 后端 API 调用（参照 zewm006 模式，OData V4） ── */
        _callApi: function(sMname, oParams, fnSuccess, fnError, sCode) {
            var sUrl = "/sap/opu/odata4/sap/zui_zt_rest_conf_o4/srvd/sap/zui_zt_rest_conf_o4/0001/conf";

            var oPayload = {
                Zznumb: sCode || "ZEWM005",
                Zzname: sMname.toUpperCase(),
                Zzfname: "ZCL_ZEWM005_TRANSFER",
                Zzipara: JSON.stringify(Object.assign(
                    { mname: sMname.toUpperCase() },
                    oParams
                ))
            };

            fetch(sUrl, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json; charset=utf-8",
                    "Accept": "application/json"
                },
                body: JSON.stringify(oPayload)
            }).then(function(oResponse) {
                if (!oResponse.ok) {
                    return oResponse.text().then(function(sText) {
                        var sMsg = sText;
                        try {
                            var oErr = JSON.parse(sText);
                            sMsg = (oErr.error && oErr.error.message && oErr.error.message.value) || sText;
                        } catch {
                            sMsg = sText;
                        }
                        throw new Error(sMsg);
                    });
                }
                return oResponse.json();
            }).then(function(oData) {
                if (oData && oData.Zzrestype === "E") {
                    fnError(oData.Zzresmsg || "Operation failed");
                } else {
                    fnSuccess({
                        restype: oData && oData.Zzrestype,
                        resmsg: oData && oData.Zzresmsg,
                        resdata: oData && oData.Zzresdata
                    });
                }
            }).catch(function(oError) {
                fnError(oError.message || "Request failed");
            });
        },

        /* ── 辅助方法 ────────────────────────────────────────── */
        _showError: function(oInput, sMessage) {
            oInput.setValueState(ValueState.Error);
            oInput.setValueStateText(sMessage);
            oInput.focus();
        },

        _clearError: function(oInput) {
            oInput.setValueState(ValueState.None);
            oInput.setValueStateText("");
        },

        _i18n: function(sKey, aArgs) {
            return this.getView().getModel("i18n").getResourceBundle().getText(sKey, aArgs);
        },

        _generateUuid: function() {
            return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
                var r = Math.random() * 16 | 0;
                return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16);
            });
        }
    });
});
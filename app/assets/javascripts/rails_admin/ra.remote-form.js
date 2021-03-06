/*
 * RailsAdmin remote form @VERSION
 *
 * License
 *
 * http://www.railsadmin.org
 *
 * Depends:
 *   jquery.ui.core.js
 *   jquery.ui.widget.js
 *   jquery.ui.dialog.js
 */
(function($) {
    $.widget("ra.remoteForm", {
        dialog: null,
        options: {
            dialogClass: "",
            width: 850
        },

        _create: function() {
            var widget = this;
            $(widget.element).bind("click", function(e){
                e.preventDefault();
                var dialog = widget._getDialog();
                $.ajax({
                    url: $(this).attr("href"),
                    dataType: 'html',
                    beforeSend: function(xhr) {
                        xhr.setRequestHeader("Accept", "text/javascript");
                    },
                    success: function(data, status, xhr) {
                        dialog.html(data);
                        widget._bindFormEvents();
                    },
                    error: function(xhr, status, error) {
                        dialog.html(xhr.responseText);
                    }
                });
            });
        },

        _bindFormEvents: function() {
            var dialog = this._getDialog(),
                form = dialog.find("form"),
                widget = this,
                saveButtonText = dialog.find("input[name=_save]").val() || dialog.find("input[name=_delete]").val(),
                cancelButtonText = dialog.find("input[name=_continue]").val();
            dialog.dialog("option", "title", $(".ui-widget-header", dialog).remove().text());
            dialog.find(".remove-for-form").remove();
            dialog.find("fieldset").css({"float": "none", "width":"100%"});
            dialog.find("fieldset legend").css({"width":"100%"});

            form.attr("data-remote", true);
            form.attr("data-type", 'json');
            form.attr("action", form.attr("action")+'?remote=true');

            $('#loadingDiv')
                .hide()  // hide it initially
                .ajaxStart(function() {
                    $(this).parent().find("form").hide();
                    $(this).show();
                })
                .ajaxStop(function() {
                    $(this).hide();
                    $(this).parent().find("form").show();
                });

            dialog.find(".submit").remove();
            dialog.find(".ra-block-content").removeClass("ra-block-content");

            var buttons = {};
            if($j("#system_import_upload_form").length == 0 && $j("#system_exporting_message").length == 0)
            {
                buttons[saveButtonText] = function() {
                    // We need to manually update CKeditor mapped textarea before ajax submit
                    if(typeof CKEDITOR != 'undefined') {
                        for ( instance in CKEDITOR.instances )
                            CKEDITOR.instances[instance].updateElement();
                    }

                    dialog.find("form").submit();
                }
            };

            if($j("#system_exporting_message").length == 0)
            {
                buttons[cancelButtonText] = function() {
                    dialog.dialog("close");
                };
            }

            dialog.dialog("option", "buttons", buttons);

            form.bind("ajax:success", function(e, data, status, xhr) {

                var json = data;
                var select = widget.element.siblings('select');

                if(widget.options.elementToUpdate)
                    var input = widget.options.elementToUpdate
                else
                    var input = widget.element.siblings('.ra-filtering-select-input');

                if(input.length > 0) {
                    input[0].value = json.label;
                }

                if(select.length > 0) {
                    select.html('<option value="' + json.id + '">' + json.label + '</option>' );
                    select[0].value = json.id;
                }
                dialog.dialog("close");
                input.change();
            });

            form.bind("ajax:error", function(e, xhr, status, error) {
                dialog.html(xhr.responseText);
                widget._bindFormEvents();
            });
        },

        _getDialog: function() {
            if (!this.dialog) {
                var widget = this;
                this.dialog = $('<div class="' + this.options.dialogClass + '"></div>').dialog({
                    autoShow: false,
                    close: function(e, ui) {
                        $(this).dialog("destroy");
                        $(this).remove();
                        widget.dialog = null;
                    },
                    modal: true,
                    width: this.options.width,
                    height: 600
                });
            }
            return this.dialog;
        }
    });
})(jQuery);
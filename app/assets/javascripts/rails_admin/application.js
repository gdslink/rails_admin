if (typeof($j) === "undefined" && typeof(jQuery) !== "undefined") {
  var $j = jQuery.noConflict();
  var $ = $j;
}

$j.ajaxSetup({
  timeout: 600000 //set request timeout to 10 minnutes
});

$j(document).ready(function($){
  $(".ra-button").not(".ui-button").button({});


  if ($("#submit-buttons").length > 0 && $("#submit-buttons").children().length == 0){
    var form = $(".remove-for-form.ra-block-toolbar.ui-state-highlight.clearfix input[type='submit']").parents('form:first');
    $("ul.submit").clone(true).appendTo("#submit-buttons");    
    $("#submit-buttons input[type='submit']").click(function(){
      form.append('<input type="hidden" name="' + $(this).attr('name') + '"/>');
      form.submit();
    })
  }

});

Event.observe(window,'load',function() {
  jQuery('#branch').change(function(e) {
      var branch_id = jQuery(this).val();
      jQuery('#commit-selects select').hide();
      jQuery('#commit-selects select').attr('disabled', true);
      jQuery('#commit-selects #' + branch_id).show();
      jQuery('#commit-selects #' + branch_id).attr('disabled', false);
  });
  jQuery('#branch').change();
});
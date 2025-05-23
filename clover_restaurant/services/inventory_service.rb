def create_category(category_data)
  logger.info "Creating new category for merchant #{@config.merchant_id}"
  logger.info "Category data: #{category_data.inspect}"
  make_request(:post, endpoint("categories"), category_data)
end

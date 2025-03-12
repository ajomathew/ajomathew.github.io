#!/bin/bash

# Prompt for the new file name
read -p "Enter the new file name (without extension): " filename

# Get the current date in yyyy-mm-dd format
current_date=$(date +%F)

# Create the new file name with the date prepended
new_filename="${current_date}-${filename}.md"

# Copy the post.md file to the new file
cp post.md "../_posts/$new_filename"

# Prompt for categories and tasks
read -p "Enter categories (comma-separated): " categories
read -p "Enter tags (comma-separated): " tasks

# Insert the front matter into the new file
cat <<EOL > "../_posts/$new_filename"
---
title: $filename
date: $current_date
categories: [$categories]
tags: [$tasks]
---

EOL

# Append the content of post.md to the new file
cat post.md >> "../_posts/$new_filename"

echo "New post created: ../_posts/$new_filename$new_filename"
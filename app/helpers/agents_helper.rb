module AgentsHelper
  # Render an agent's avatar: the uploaded image if one is attached, otherwise
  # the color + initials circle. size_classes/text_size are Tailwind utility
  # strings shared by both branches; variant_px is the square pixel size to
  # resize an uploaded image to (via ruby-vips).
  def agent_avatar(agent, size_classes:, text_size:, variant_px:)
    if agent.avatar.attached?
      image_tag agent.avatar_variant(variant_px),
                class: "#{size_classes} rounded-full object-cover", alt: agent.name
    else
      tag.div(class: "#{size_classes} rounded-full #{agent.avatar_bg_class} flex items-center justify-center") do
        tag.span agent.initials, class: "#{text_size} font-bold #{agent.avatar_text_class}"
      end
    end
  end
end

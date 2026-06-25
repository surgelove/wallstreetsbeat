// Haptics implementation for love.system.vibrate on iOS
// Uses UIImpactFeedbackGenerator for subtle tactile feedback

#import <UIKit/UIKit.h>

namespace love
{
namespace haptics
{

void vibrate(double duration)
{
    // Very short = soft tap (gentlest), short = light, longer = medium, longest = heavy
    UIImpactFeedbackStyle style = UIImpactFeedbackStyleSoft;
    if (duration > 0.02)
        style = UIImpactFeedbackStyleLight;
    if (duration > 0.1)
        style = UIImpactFeedbackStyleMedium;
    if (duration > 0.3)
        style = UIImpactFeedbackStyleHeavy;

    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
    [gen prepare];
    [gen impactOccurred];
}

} // haptics
} // love

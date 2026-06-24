// Haptics implementation for love.system.vibrate on iOS
// Uses UIImpactFeedbackGenerator for subtle tactile feedback

#import <UIKit/UIKit.h>

namespace love
{
namespace haptics
{

void vibrate(double duration)
{
    // Very short = light tap, longer = medium tap
    UIImpactFeedbackStyle style = UIImpactFeedbackStyleLight;
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

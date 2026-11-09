// SPDX-License-Identifier: GPL-2.0
/*
 * Samsung S5K5E8 5MP CSI-2 sensor driver (ugglite front camera).
 *
 * Out-of-tree V4L2 subdev for the Redmi Note 5A (ugglite) front module:
 * CCI1 address 0x2d, 24 MHz MCLK1, reset GPIO40, standby GPIO39, both
 * ACTIVE_LOW, 2 CSI-2 data lanes.
 *
 * The five mode tables are byte-for-byte extractions from the stock
 * libmmcamera_s5k5e8_{oef0501,f5e8ybf}_d6.so (both HAL variants share
 * identical .text/.rodata).  A register record is (u16 addr, u8 value);
 * 16-bit quantities are split over two consecutive byte registers.
 *
 * Deliberately NOT invented here:
 *   - 0x0104 group hold: absent from the HAL mode tables, not written.
 *   - any common init preamble: the HAL tables are complete mode lists in
 *     ascending register order and are written as-is.
 *   - 0x3Bxx CSI registers: S5K5E8 lane configuration is 0x0114 (value 1,
 *     i.e. two data lanes); 0x3Bxx belongs to a different sensor family.
 *   - stream-on is 0x0100 = 0x01 (Samsung standard, absent from the tables).
 */
#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/of_device.h>
#include <linux/pm_runtime.h>
#include <linux/regmap.h>
#include <linux/regulator/consumer.h>

#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>
#include <media/v4l2-fwnode.h>

#include "s5k5e8_modes.h"

#define S5K5E8_MCLK			24000000
#define S5K5E8_DATA_LANES		2
#define S5K5E8_MAX_COLOR_DEPTH		10

#define S5K5E8_REG_CHIP_ID		0x0000
#define S5K5E8_CHIP_ID			0x5e80

#define S5K5E8_REG_MODE_SELECT		0x0100
#define S5K5E8_MODE_STANDBY		0x00
#define S5K5E8_MODE_STREAMING		0x01

#define S5K5E8_REG_FLL			0x0340
#define S5K5E8_REG_LLP			0x0342

#define S5K5E8_REG_EXPOSURE		0x0202
#define S5K5E8_EXPOSURE_MIN		7
#define S5K5E8_EXPOSURE_MAX_MARGIN	8
#define S5K5E8_EXPOSURE_STEP		1

#define S5K5E8_REG_ANALOG_GAIN		0x0204
#define S5K5E8_ANAL_GAIN_MIN		0x0100
#define S5K5E8_ANAL_GAIN_MAX		0x0fff
#define S5K5E8_ANAL_GAIN_DEFAULT	0x0100
#define S5K5E8_ANAL_GAIN_STEP		1

#define S5K5E8_REG_DIG_GAIN		0x020e
#define S5K5E8_DGTL_GAIN_MIN		0x0100
#define S5K5E8_DGTL_GAIN_MAX		0x0fff
#define S5K5E8_DGTL_GAIN_DEFAULT	0x0100
#define S5K5E8_DGTL_GAIN_STEP		1

static const char * const s5k5e8_supply_names[] = { "avdd", "dvdd", "vio" };
#define S5K5E8_NUM_SUPPLIES		ARRAY_SIZE(s5k5e8_supply_names)

/* op_pixel_clk from the HAL descriptors: 167.2 MHz and 120 MHz.
 * link_freq = op_pixel_clk * 10 bit / (2 lanes * 2 DDR) = op * 2.5.
 */
#define S5K5E8_LINK_FREQ_418MHZ		418000000
#define S5K5E8_LINK_FREQ_300MHZ		300000000

enum {
	S5K5E8_LINK_FREQ_418MHZ_INDEX,
	S5K5E8_LINK_FREQ_300MHZ_INDEX,
};

static const s64 link_freq_menu_items[] = {
	S5K5E8_LINK_FREQ_418MHZ,
	S5K5E8_LINK_FREQ_300MHZ,
};

struct s5k5e8_mode {
	u32 width;
	u32 height;
	u32 llp;
	u32 fll;
	u32 pixel_rate;
	u32 link_freq_index;
	const struct s5k5e8_reg *regs;
	u32 num_regs;
};

/* Mode order mirrors the HAL descriptor array at 0x76fc8. */
static const struct s5k5e8_mode s5k5e8_modes[] = {
	{
		.width = 2592,
		.height = 1944,
		.llp = 2856,
		.fll = 1968,
		.pixel_rate = 167200000,
		.link_freq_index = S5K5E8_LINK_FREQ_418MHZ_INDEX,
		.regs = s5k5e8_mode_2592x1944_regs,
		.num_regs = ARRAY_SIZE(s5k5e8_mode_2592x1944_regs),
	}, {
		.width = 1296,
		.height = 972,
		.llp = 5200,
		.fll = 1062,
		.pixel_rate = 167200000,
		.link_freq_index = S5K5E8_LINK_FREQ_418MHZ_INDEX,
		.regs = s5k5e8_mode_1296x972_regs,
		.num_regs = ARRAY_SIZE(s5k5e8_mode_1296x972_regs),
	}, {
		.width = 1304,
		.height = 980,
		.llp = 2784,
		.fll = 1009,
		.pixel_rate = 120000000,
		.link_freq_index = S5K5E8_LINK_FREQ_300MHZ_INDEX,
		.regs = s5k5e8_mode_1304x980_regs,
		.num_regs = ARRAY_SIZE(s5k5e8_mode_1304x980_regs),
	}, {
		.width = 800,
		.height = 600,
		.llp = 2816,
		.fll = 662,
		.pixel_rate = 167200000,
		.link_freq_index = S5K5E8_LINK_FREQ_418MHZ_INDEX,
		.regs = s5k5e8_mode_800x600_regs,
		.num_regs = ARRAY_SIZE(s5k5e8_mode_800x600_regs),
	}, {
		.width = 640,
		.height = 480,
		.llp = 2816,
		.fll = 507,
		.pixel_rate = 167200000,
		.link_freq_index = S5K5E8_LINK_FREQ_418MHZ_INDEX,
		.regs = s5k5e8_mode_640x480_regs,
		.num_regs = ARRAY_SIZE(s5k5e8_mode_640x480_regs),
	},
};

struct s5k5e8 {
	struct v4l2_subdev sd;
	struct regmap *rmap;
	struct media_pad pad;
	struct v4l2_ctrl_handler ctrl_handler;

	struct v4l2_ctrl *link_freq;
	struct v4l2_ctrl *pixel_rate;
	struct v4l2_ctrl *vblank;
	struct v4l2_ctrl *hblank;
	struct v4l2_ctrl *exposure;

	struct regulator_bulk_data supplies[S5K5E8_NUM_SUPPLIES];
	struct clk *mclk;
	struct gpio_desc *reset_gpio;
	struct gpio_desc *standby_gpio;
	int enabled;

	const struct s5k5e8_mode *cur_mode;

	struct mutex lock;
	bool streaming;
};

static inline struct s5k5e8 *to_s5k5e8(struct v4l2_subdev *sd)
{
	return container_of(sd, struct s5k5e8, sd);
}

/* 16-bit register value stored big-endian in two 8-bit registers. */
static int s5k5e8_write16(struct s5k5e8 *s5k5e8, u16 reg, u16 val)
{
	u8 data[2] = { val >> 8, val & 0xff };

	return regmap_bulk_write(s5k5e8->rmap, reg, data, sizeof(data));
}

static int s5k5e8_read16(struct s5k5e8 *s5k5e8, u16 reg, u16 *val)
{
	u8 data[2];
	int ret;

	ret = regmap_bulk_read(s5k5e8->rmap, reg, data, sizeof(data));
	if (ret)
		return ret;
	*val = (data[0] << 8) | data[1];

	return 0;
}

static int s5k5e8_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct s5k5e8 *s5k5e8 = container_of(ctrl->handler, struct s5k5e8,
					     ctrl_handler);
	struct i2c_client *client = v4l2_get_subdevdata(&s5k5e8->sd);
	s64 exposure_max;
	int ret = 0;

	if (ctrl->id == V4L2_CID_VBLANK) {
		/* FLL is programmed as height + vblank below; the maximum
		 * exposure is that frame length minus the margin.  Adding the
		 * mode FLL and vblank here subtracted the height twice and
		 * left only 46 lines on the 640x480 mode. */
		exposure_max = s5k5e8->cur_mode->height + ctrl->val -
			       S5K5E8_EXPOSURE_MAX_MARGIN;
		__v4l2_ctrl_modify_range(s5k5e8->exposure,
					 s5k5e8->exposure->minimum,
					 exposure_max, s5k5e8->exposure->step,
					 exposure_max);
	}

	if (!pm_runtime_get_if_in_use(&client->dev))
		return 0;

	switch (ctrl->id) {
	case V4L2_CID_EXPOSURE:
		ret = s5k5e8_write16(s5k5e8, S5K5E8_REG_EXPOSURE, ctrl->val);
		break;
	case V4L2_CID_ANALOGUE_GAIN:
		ret = s5k5e8_write16(s5k5e8, S5K5E8_REG_ANALOG_GAIN, ctrl->val);
		break;
	case V4L2_CID_DIGITAL_GAIN:
		ret = s5k5e8_write16(s5k5e8, S5K5E8_REG_DIG_GAIN, ctrl->val);
		break;
	case V4L2_CID_VBLANK:
		ret = s5k5e8_write16(s5k5e8, S5K5E8_REG_FLL,
				     s5k5e8->cur_mode->height + ctrl->val);
		break;
	default:
		ret = -EINVAL;
		break;
	}

	pm_runtime_put(&client->dev);

	return ret;
}

static const struct v4l2_ctrl_ops s5k5e8_ctrl_ops = {
	.s_ctrl = s5k5e8_set_ctrl,
};

static int s5k5e8_init_controls(struct s5k5e8 *s5k5e8)
{
	struct i2c_client *client = v4l2_get_subdevdata(&s5k5e8->sd);
	struct v4l2_ctrl_handler *ctrl_hdlr = &s5k5e8->ctrl_handler;
	struct v4l2_fwnode_device_properties props;
	s64 exposure_max, h_blank, rate_max = INT_MIN, rate_min = INT_MAX;
	int ret, i;

	ret = v4l2_ctrl_handler_init(ctrl_hdlr, 8);
	if (ret)
		return ret;

	ctrl_hdlr->lock = &s5k5e8->lock;

	for (i = 0; i < ARRAY_SIZE(s5k5e8_modes); i++) {
		rate_max = max(rate_max, (s64)s5k5e8_modes[i].pixel_rate);
		rate_min = min(rate_min, (s64)s5k5e8_modes[i].pixel_rate);
	}

	s5k5e8->link_freq = v4l2_ctrl_new_int_menu(ctrl_hdlr,
			&s5k5e8_ctrl_ops, V4L2_CID_LINK_FREQ,
			ARRAY_SIZE(link_freq_menu_items) - 1, 0,
			link_freq_menu_items);
	if (s5k5e8->link_freq)
		s5k5e8->link_freq->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	s5k5e8->pixel_rate = v4l2_ctrl_new_std(ctrl_hdlr, &s5k5e8_ctrl_ops,
			V4L2_CID_PIXEL_RATE, rate_min, rate_max, 1,
			s5k5e8->cur_mode->pixel_rate);

	s5k5e8->vblank = v4l2_ctrl_new_std(ctrl_hdlr, &s5k5e8_ctrl_ops,
			V4L2_CID_VBLANK, 4,
			0xffff - s5k5e8->cur_mode->height, 1,
			s5k5e8->cur_mode->fll - s5k5e8->cur_mode->height);

	h_blank = s5k5e8->cur_mode->llp - s5k5e8->cur_mode->width;
	s5k5e8->hblank = v4l2_ctrl_new_std(ctrl_hdlr, &s5k5e8_ctrl_ops,
			V4L2_CID_HBLANK, h_blank, h_blank, 1, h_blank);
	if (s5k5e8->hblank)
		s5k5e8->hblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	v4l2_ctrl_new_std(ctrl_hdlr, &s5k5e8_ctrl_ops, V4L2_CID_ANALOGUE_GAIN,
			S5K5E8_ANAL_GAIN_MIN, S5K5E8_ANAL_GAIN_MAX,
			S5K5E8_ANAL_GAIN_STEP, S5K5E8_ANAL_GAIN_DEFAULT);
	v4l2_ctrl_new_std(ctrl_hdlr, &s5k5e8_ctrl_ops, V4L2_CID_DIGITAL_GAIN,
			S5K5E8_DGTL_GAIN_MIN, S5K5E8_DGTL_GAIN_MAX,
			S5K5E8_DGTL_GAIN_STEP, S5K5E8_DGTL_GAIN_DEFAULT);

	exposure_max = s5k5e8->cur_mode->fll - S5K5E8_EXPOSURE_MAX_MARGIN;
	s5k5e8->exposure = v4l2_ctrl_new_std(ctrl_hdlr, &s5k5e8_ctrl_ops,
			V4L2_CID_EXPOSURE, S5K5E8_EXPOSURE_MIN, exposure_max,
			S5K5E8_EXPOSURE_STEP, exposure_max);

	ret = v4l2_fwnode_device_parse(&client->dev, &props);
	if (ret)
		return ret;

	ret = v4l2_ctrl_new_fwnode_properties(ctrl_hdlr, &s5k5e8_ctrl_ops,
					      &props);
	if (ret)
		return ret;

	if (ctrl_hdlr->error)
		return ctrl_hdlr->error;

	s5k5e8->sd.ctrl_handler = ctrl_hdlr;

	return 0;
}

static void s5k5e8_assign_pad_format(const struct s5k5e8_mode *mode,
				     struct v4l2_mbus_framefmt *fmt)
{
	fmt->width = mode->width;
	fmt->height = mode->height;
	fmt->code = MEDIA_BUS_FMT_SGRBG10_1X10;
	fmt->field = V4L2_FIELD_NONE;
}

static int s5k5e8_start_streaming(struct s5k5e8 *s5k5e8)
{
	struct i2c_client *client = v4l2_get_subdevdata(&s5k5e8->sd);
	const struct s5k5e8_mode *mode = s5k5e8->cur_mode;
	unsigned int i;
	int ret;

	for (i = 0; i < mode->num_regs; i++) {
		ret = regmap_write(s5k5e8->rmap, mode->regs[i].reg,
				   mode->regs[i].val);
		if (ret) {
			dev_err(&client->dev, "failed to write mode reg 0x%04x: %d\n",
				mode->regs[i].reg, ret);
			return ret;
		}
	}

	ret = __v4l2_ctrl_handler_setup(s5k5e8->sd.ctrl_handler);
	if (ret)
		return ret;

	ret = regmap_write(s5k5e8->rmap, S5K5E8_REG_MODE_SELECT,
			   S5K5E8_MODE_STREAMING);
	if (ret) {
		dev_err(&client->dev, "failed to start streaming: %d\n", ret);
		return ret;
	}

	usleep_range(10000, 11000);

	return 0;
}

static void s5k5e8_stop_streaming(struct s5k5e8 *s5k5e8)
{
	struct i2c_client *client = v4l2_get_subdevdata(&s5k5e8->sd);

	if (regmap_write(s5k5e8->rmap, S5K5E8_REG_MODE_SELECT,
			 S5K5E8_MODE_STANDBY))
		dev_err(&client->dev, "failed to stop streaming\n");
}

static int s5k5e8_set_stream(struct v4l2_subdev *sd, int enable)
{
	struct s5k5e8 *s5k5e8 = to_s5k5e8(sd);
	struct i2c_client *client = v4l2_get_subdevdata(sd);
	int ret = 0;

	if (s5k5e8->streaming == enable)
		return 0;

	mutex_lock(&s5k5e8->lock);
	if (enable) {
		ret = pm_runtime_get_sync(&client->dev);
		if (ret < 0) {
			pm_runtime_put_noidle(&client->dev);
			mutex_unlock(&s5k5e8->lock);
			return ret;
		}

		ret = s5k5e8_start_streaming(s5k5e8);
		if (ret) {
			enable = 0;
			s5k5e8_stop_streaming(s5k5e8);
			pm_runtime_put(&client->dev);
		}
	} else {
		s5k5e8_stop_streaming(s5k5e8);
		pm_runtime_put(&client->dev);
	}

	s5k5e8->streaming = enable;
	mutex_unlock(&s5k5e8->lock);

	return ret;
}

static int s5k5e8_power_on(struct s5k5e8 *s5k5e8)
{
	struct i2c_client *client = v4l2_get_subdevdata(&s5k5e8->sd);
	struct device *dev = &client->dev;
	int ret;

	if (s5k5e8->enabled++)
		return 0;

	ret = regulator_bulk_enable(S5K5E8_NUM_SUPPLIES, s5k5e8->supplies);
	if (ret) {
		dev_err(dev, "failed to enable regulators: %d\n", ret);
		goto err_dec;
	}

	ret = clk_set_rate(s5k5e8->mclk, S5K5E8_MCLK);
	if (ret) {
		dev_err(dev, "failed to set MCLK rate: %d\n", ret);
		goto reg_off;
	}

	ret = clk_prepare_enable(s5k5e8->mclk);
	if (ret) {
		dev_err(dev, "failed to enable MCLK: %d\n", ret);
		goto reg_off;
	}

	usleep_range(1000, 2000);

	/* Both lines are ACTIVE_LOW in DT: 1 = asserted. */
	gpiod_set_value_cansleep(s5k5e8->reset_gpio, 0);
	usleep_range(10000, 11000);
	gpiod_set_value_cansleep(s5k5e8->standby_gpio, 0);
	usleep_range(10000, 11000);

	return 0;

reg_off:
	regulator_bulk_disable(S5K5E8_NUM_SUPPLIES, s5k5e8->supplies);
err_dec:
	s5k5e8->enabled--;
	return ret;
}

static int s5k5e8_power_off(struct s5k5e8 *s5k5e8)
{
	if (--s5k5e8->enabled > 0)
		return 0;

	gpiod_set_value_cansleep(s5k5e8->standby_gpio, 1);
	gpiod_set_value_cansleep(s5k5e8->reset_gpio, 1);
	clk_disable_unprepare(s5k5e8->mclk);
	regulator_bulk_disable(S5K5E8_NUM_SUPPLIES, s5k5e8->supplies);

	return 0;
}

static int s5k5e8_set_format(struct v4l2_subdev *sd,
			     struct v4l2_subdev_state *sd_state,
			     struct v4l2_subdev_format *fmt)
{
	struct s5k5e8 *s5k5e8 = to_s5k5e8(sd);
	const struct s5k5e8_mode *mode;
	s32 vblank_def, h_blank;
	s64 exposure_max;

	mode = v4l2_find_nearest_size(s5k5e8_modes, ARRAY_SIZE(s5k5e8_modes),
				      width, height, fmt->format.width,
				      fmt->format.height);

	mutex_lock(&s5k5e8->lock);
	s5k5e8_assign_pad_format(mode, &fmt->format);
	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY) {
		*v4l2_subdev_state_get_format(sd_state, fmt->pad) = fmt->format;
	} else {
		s5k5e8->cur_mode = mode;
		__v4l2_ctrl_s_ctrl(s5k5e8->link_freq, mode->link_freq_index);
		__v4l2_ctrl_s_ctrl_int64(s5k5e8->pixel_rate, mode->pixel_rate);

		vblank_def = mode->fll - mode->height;
		__v4l2_ctrl_modify_range(s5k5e8->vblank, 4,
					 0xffff - mode->height, 1, vblank_def);
		__v4l2_ctrl_s_ctrl(s5k5e8->vblank, vblank_def);

		h_blank = mode->llp - mode->width;
		__v4l2_ctrl_modify_range(s5k5e8->hblank, h_blank, h_blank, 1,
					 h_blank);

		exposure_max = mode->fll - S5K5E8_EXPOSURE_MAX_MARGIN;
		__v4l2_ctrl_modify_range(s5k5e8->exposure,
					 S5K5E8_EXPOSURE_MIN, exposure_max,
					 S5K5E8_EXPOSURE_STEP, exposure_max);
	}
	mutex_unlock(&s5k5e8->lock);

	return 0;
}

static int s5k5e8_get_format(struct v4l2_subdev *sd,
			     struct v4l2_subdev_state *sd_state,
			     struct v4l2_subdev_format *fmt)
{
	struct s5k5e8 *s5k5e8 = to_s5k5e8(sd);

	mutex_lock(&s5k5e8->lock);
	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY)
		fmt->format = *v4l2_subdev_state_get_format(sd_state, fmt->pad);
	else
		s5k5e8_assign_pad_format(s5k5e8->cur_mode, &fmt->format);
	mutex_unlock(&s5k5e8->lock);

	return 0;
}

static int s5k5e8_enum_mbus_code(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *sd_state,
				 struct v4l2_subdev_mbus_code_enum *code)
{
	if (code->index > 0)
		return -EINVAL;

	code->code = MEDIA_BUS_FMT_SGRBG10_1X10;

	return 0;
}

static int s5k5e8_enum_frame_size(struct v4l2_subdev *sd,
				  struct v4l2_subdev_state *sd_state,
				  struct v4l2_subdev_frame_size_enum *fse)
{
	if (fse->index >= ARRAY_SIZE(s5k5e8_modes))
		return -EINVAL;

	if (fse->code != MEDIA_BUS_FMT_SGRBG10_1X10)
		return -EINVAL;

	fse->min_width = s5k5e8_modes[fse->index].width;
	fse->max_width = fse->min_width;
	fse->min_height = s5k5e8_modes[fse->index].height;
	fse->max_height = fse->min_height;

	return 0;
}

static int s5k5e8_open(struct v4l2_subdev *sd, struct v4l2_subdev_fh *fh)
{
	struct s5k5e8 *s5k5e8 = to_s5k5e8(sd);

	mutex_lock(&s5k5e8->lock);
	s5k5e8_assign_pad_format(&s5k5e8_modes[0],
				 v4l2_subdev_state_get_format(fh->state, 0));
	mutex_unlock(&s5k5e8->lock);

	return 0;
}

static const struct v4l2_subdev_video_ops s5k5e8_video_ops = {
	.s_stream = s5k5e8_set_stream,
};

static const struct v4l2_subdev_pad_ops s5k5e8_pad_ops = {
	.set_fmt = s5k5e8_set_format,
	.get_fmt = s5k5e8_get_format,
	.enum_mbus_code = s5k5e8_enum_mbus_code,
	.enum_frame_size = s5k5e8_enum_frame_size,
};

static const struct v4l2_subdev_ops s5k5e8_subdev_ops = {
	.video = &s5k5e8_video_ops,
	.pad = &s5k5e8_pad_ops,
};

static const struct media_entity_operations s5k5e8_entity_ops = {
	.link_validate = v4l2_subdev_link_validate,
};

static const struct v4l2_subdev_internal_ops s5k5e8_internal_ops = {
	.open = s5k5e8_open,
};

static int s5k5e8_identify(struct s5k5e8 *s5k5e8)
{
	struct i2c_client *client = v4l2_get_subdevdata(&s5k5e8->sd);
	u16 id;
	int ret;

	ret = s5k5e8_read16(s5k5e8, S5K5E8_REG_CHIP_ID, &id);
	if (ret)
		return ret;

	dev_info(&client->dev, "chip ID 0x%04x (expected 0x%04x)\n",
		 id, S5K5E8_CHIP_ID);
	if (id != S5K5E8_CHIP_ID)
		return -ENXIO;

	return 0;
}

static int s5k5e8_check_hwcfg(struct device *dev)
{
	struct v4l2_fwnode_endpoint bus_cfg = {
		.bus_type = V4L2_MBUS_CSI2_DPHY,
	};
	struct fwnode_handle *ep;
	struct fwnode_handle *fwnode = dev_fwnode(dev);
	int ret;

	if (!fwnode)
		return -ENXIO;

	ep = fwnode_graph_get_next_endpoint(fwnode, NULL);
	if (!ep)
		return -ENXIO;

	ret = v4l2_fwnode_endpoint_alloc_parse(ep, &bus_cfg);
	fwnode_handle_put(ep);
	if (ret)
		return ret;

	if (bus_cfg.bus.mipi_csi2.num_data_lanes != S5K5E8_DATA_LANES) {
		dev_err(dev, "expected %u CSI-2 data lanes, DT has %u\n",
			S5K5E8_DATA_LANES,
			bus_cfg.bus.mipi_csi2.num_data_lanes);
		ret = -EINVAL;
	}

	v4l2_fwnode_endpoint_free(&bus_cfg);

	return ret;
}

static int s5k5e8_of_init(struct s5k5e8 *s5k5e8, struct device *dev)
{
	int i, ret;

	for (i = 0; i < S5K5E8_NUM_SUPPLIES; i++)
		s5k5e8->supplies[i].supply = s5k5e8_supply_names[i];

	ret = devm_regulator_bulk_get(dev, S5K5E8_NUM_SUPPLIES,
				      s5k5e8->supplies);
	if (ret)
		return dev_err_probe(dev, ret, "failed to get regulators\n");

	s5k5e8->mclk = devm_clk_get(dev, NULL);
	if (IS_ERR(s5k5e8->mclk))
		return dev_err_probe(dev, PTR_ERR(s5k5e8->mclk),
				     "failed to get MCLK\n");

	s5k5e8->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(s5k5e8->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(s5k5e8->reset_gpio),
				     "failed to get reset GPIO\n");

	s5k5e8->standby_gpio = devm_gpiod_get(dev, "standby", GPIOD_OUT_HIGH);
	if (IS_ERR(s5k5e8->standby_gpio))
		return dev_err_probe(dev, PTR_ERR(s5k5e8->standby_gpio),
				     "failed to get standby GPIO\n");

	return 0;
}

static const struct regmap_config s5k5e8_regmap_config = {
	.reg_bits = 16,
	.val_bits = 8,
	.cache_type = REGCACHE_NONE,
};

static void s5k5e8_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct s5k5e8 *s5k5e8 = to_s5k5e8(sd);

	v4l2_async_unregister_subdev(sd);
	media_entity_cleanup(&sd->entity);
	v4l2_ctrl_handler_free(sd->ctrl_handler);
	pm_runtime_disable(&client->dev);
	if (!pm_runtime_status_suspended(&client->dev))
		s5k5e8_power_off(s5k5e8);
	mutex_destroy(&s5k5e8->lock);
}

static int s5k5e8_probe(struct i2c_client *client)
{
	struct s5k5e8 *s5k5e8;
	int ret;

	s5k5e8 = devm_kzalloc(&client->dev, sizeof(*s5k5e8), GFP_KERNEL);
	if (!s5k5e8)
		return -ENOMEM;

	ret = s5k5e8_of_init(s5k5e8, &client->dev);
	if (ret)
		return ret;

	ret = s5k5e8_check_hwcfg(&client->dev);
	if (ret)
		return dev_err_probe(&client->dev, ret,
				     "failed to check HW configuration\n");

	s5k5e8->rmap = devm_regmap_init_i2c(client, &s5k5e8_regmap_config);
	if (IS_ERR_OR_NULL(s5k5e8->rmap))
		return dev_err_probe(&client->dev,
				     PTR_ERR(s5k5e8->rmap) ?: -ENODATA,
				     "failed to initialize regmap\n");

	v4l2_i2c_subdev_init(&s5k5e8->sd, client, &s5k5e8_subdev_ops);

	ret = s5k5e8_power_on(s5k5e8);
	if (ret)
		return dev_err_probe(&client->dev, ret,
				     "failed to power on sensor\n");

	ret = s5k5e8_identify(s5k5e8);
	if (ret)
		goto power_off;

	mutex_init(&s5k5e8->lock);
	s5k5e8->cur_mode = &s5k5e8_modes[4];	/* 640x480 first frame */

	ret = s5k5e8_init_controls(s5k5e8);
	if (ret) {
		dev_err(&client->dev, "failed to init controls: %d\n", ret);
		goto free_ctrls;
	}

	snprintf(s5k5e8->sd.name, sizeof(s5k5e8->sd.name),
		 "s5k5e8 %s", dev_name(&client->dev));

	s5k5e8->sd.internal_ops = &s5k5e8_internal_ops;
	s5k5e8->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	s5k5e8->sd.entity.ops = &s5k5e8_entity_ops;
	s5k5e8->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;
	s5k5e8->pad.flags = MEDIA_PAD_FL_SOURCE;
	ret = media_entity_pads_init(&s5k5e8->sd.entity, 1, &s5k5e8->pad);
	if (ret) {
		dev_err(&client->dev, "failed to init entity pads: %d\n", ret);
		goto free_ctrls;
	}

	ret = v4l2_async_register_subdev_sensor(&s5k5e8->sd);
	if (ret) {
		dev_err(&client->dev, "failed to register V4L2 subdev: %d\n",
			ret);
		goto cleanup_entity;
	}

	pm_runtime_set_active(&client->dev);
	pm_runtime_enable(&client->dev);
	pm_runtime_idle(&client->dev);

	return 0;

cleanup_entity:
	media_entity_cleanup(&s5k5e8->sd.entity);
free_ctrls:
	v4l2_ctrl_handler_free(&s5k5e8->ctrl_handler);
	mutex_destroy(&s5k5e8->lock);
power_off:
	s5k5e8_power_off(s5k5e8);

	return ret;
}

static int s5k5e8_runtime_suspend(struct device *dev)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(to_i2c_client(dev));

	return s5k5e8_power_off(to_s5k5e8(sd));
}

static int s5k5e8_runtime_resume(struct device *dev)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(to_i2c_client(dev));

	return s5k5e8_power_on(to_s5k5e8(sd));
}

static const struct dev_pm_ops s5k5e8_pm_ops = {
	SET_RUNTIME_PM_OPS(s5k5e8_runtime_suspend, s5k5e8_runtime_resume, NULL)
};

static const struct of_device_id s5k5e8_of_match[] = {
	{ .compatible = "samsung,s5k5e8" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, s5k5e8_of_match);

static struct i2c_driver s5k5e8_i2c_driver = {
	.driver = {
		.name = "s5k5e8",
		.pm = &s5k5e8_pm_ops,
		.of_match_table = of_match_ptr(s5k5e8_of_match),
	},
	.probe = s5k5e8_probe,
	.remove = s5k5e8_remove,
};

module_i2c_driver(s5k5e8_i2c_driver);

MODULE_DESCRIPTION("Samsung S5K5E8 front camera sensor driver (ugglite)");
MODULE_AUTHOR("ztOS ugglite bring-up");
MODULE_LICENSE("GPL v2");

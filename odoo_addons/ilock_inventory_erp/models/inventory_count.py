from odoo import _, api, fields, models
from odoo.exceptions import UserError


class IlockInventoryCount(models.Model):
    _name = 'ilock.inventory.count'
    _description = 'I LOCK Inventory Count'
    _order = 'count_date desc, id desc'

    name = fields.Char(default=lambda self: _('New'), required=True, copy=False, readonly=True)
    count_date = fields.Date(default=fields.Date.context_today, required=True)
    warehouse_id = fields.Many2one('stock.warehouse', required=True)
    location_id = fields.Many2one(
        'stock.location', required=True,
        domain="[('usage', '=', 'internal'), ('warehouse_id', '=', warehouse_id)]",
    )
    counter_id = fields.Many2one('res.users', string='Counted By', default=lambda self: self.env.user, required=True)
    state = fields.Selection([('draft', 'Draft'), ('counting', 'Counting'), ('validated', 'Validated'), ('cancelled', 'Cancelled')], default='draft', required=True)
    line_ids = fields.One2many('ilock.inventory.count.line', 'count_id', string='Count Lines')
    note = fields.Text()
    company_id = fields.Many2one(related='warehouse_id.company_id', store=True, readonly=True)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', _('New')) == _('New'):
                vals['name'] = self.env['ir.sequence'].next_by_code('ilock.inventory.count') or _('New')
        return super().create(vals_list)

    def action_start_count(self):
        for record in self:
            if not record.location_id:
                raise UserError(_('Choose an internal location before loading quantities.'))
            record.line_ids.unlink()
            quants = self.env['stock.quant'].search([
                ('location_id', 'child_of', record.location_id.id),
                ('product_id.type', '=', 'consu'),
            ])
            grouped = {}
            for quant in quants:
                key = (quant.product_id.id, quant.location_id.id, quant.lot_id.id)
                grouped[key] = grouped.get(key, 0.0) + quant.quantity
            record.line_ids = [(0, 0, {
                'product_id': product_id, 'location_id': location_id, 'lot_id': lot_id or False,
                'theoretical_qty': quantity, 'counted_qty': quantity,
            }) for (product_id, location_id, lot_id), quantity in grouped.items()]
            record.state = 'counting'
        return True

    def action_validate(self):
        for record in self:
            if record.state != 'counting':
                raise UserError(_('Only an active count can be validated.'))
            for line in record.line_ids:
                if line.counted_qty < 0:
                    raise UserError(_('Counted quantities cannot be negative.'))
                quant = self.env['stock.quant'].search([
                    ('product_id', '=', line.product_id.id), ('location_id', '=', line.location_id.id),
                    ('lot_id', '=', line.lot_id.id),
                ], limit=1)
                if not quant:
                    quant = self.env['stock.quant'].create({'product_id': line.product_id.id, 'location_id': line.location_id.id, 'lot_id': line.lot_id.id or False})
                quant.inventory_quantity = line.counted_qty
                quant.action_apply_inventory()
            record.state = 'validated'
        return True

    def action_cancel(self):
        self.write({'state': 'cancelled'})


class IlockInventoryCountLine(models.Model):
    _name = 'ilock.inventory.count.line'
    _description = 'I LOCK Inventory Count Line'
    _order = 'product_id'

    count_id = fields.Many2one('ilock.inventory.count', required=True, ondelete='cascade')
    product_id = fields.Many2one('product.product', required=True)
    location_id = fields.Many2one('stock.location', required=True)
    lot_id = fields.Many2one('stock.lot')
    product_uom_id = fields.Many2one(related='product_id.uom_id', readonly=True)
    theoretical_qty = fields.Float(readonly=True)
    counted_qty = fields.Float(required=True)
    difference_qty = fields.Float(compute='_compute_difference_qty', readonly=True)

    @api.depends('theoretical_qty', 'counted_qty')
    def _compute_difference_qty(self):
        for line in self:
            line.difference_qty = line.counted_qty - line.theoretical_qty
